"""One user's AI Ready services: PostgreSQL, MLflow and Airflow.

    ai_ready_services.py run   start the services; stay until one exits or SIGTERM
    ai_ready_services.py env   print the exports notebooks and terminals need

Everything listens on loopback. Jupyter Server Proxy is the only way in, so
each request passes the notebook server's login first. State (databases,
Airflow logs, MLflow artifacts, generated credentials) lives in ~/.ai-ready.
"""

import base64
import json
import os
from pathlib import Path
import secrets
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from typing import NamedTuple
from urllib.parse import urlsplit

PREFIX = Path("/opt/ai-ready")
ENV_BIN = PREFIX / "env/bin"
AIRFLOW_BIN = PREFIX / "airflow/bin"
UPSTREAM = PREFIX / "upstream"

POSTGRES_PORT = 5432
MLFLOW_PORT = 5000
AIRFLOW_PORT = 8080
POSTGRES_USER = "aiready"
DATABASES = ("airflow", "mlflow")

STOP_SECONDS = 25
POSTGRES_STOP_SECONDS = 8


class Session(NamedTuple):
    """Where this session keeps its files and how its browser reaches it."""

    state: Path
    content: Path
    origin: str
    base_path: str

    @classmethod
    def from_environ(cls):
        home = Path.home()
        return cls(
            state=home / ".ai-ready",
            content=home / "ai-ready",
            origin=os.environ.get("AI_READY_PUBLIC_ORIGIN", "http://127.0.0.1:8888").rstrip("/"),
            base_path=os.environ.get("JUPYTERHUB_SERVICE_PREFIX", "/").rstrip("/") + "/",
        )

    @property
    def mlflow_path(self):
        return self.base_path + "mlflow"

    @property
    def airflow_path(self):
        return self.base_path + "airflow"


class Service(NamedTuple):
    name: str
    argv: list
    stop_signal: signal.Signals


class Stop(Exception):
    """The session is ending: SIGTERM or SIGINT arrived."""


def log(message):
    print(f"[ai-ready] {message}", flush=True)


def notebook_env(session):
    """What notebooks, terminals and DAG tasks read to find MLflow."""
    return {
        "MLFLOW_TRACKING_URI": f"http://127.0.0.1:{MLFLOW_PORT}{session.mlflow_path}",
        "MLFLOW_EXTERNAL_URL": session.origin + session.mlflow_path,
    }


def database_url(credentials, database):
    return (f"postgresql+psycopg2://{POSTGRES_USER}:{credentials['postgres']}"
            f"@127.0.0.1:{POSTGRES_PORT}/{database}")


def service_env(session, credentials):
    return {
        **os.environ,
        **notebook_env(session),
        "PATH": f"{AIRFLOW_BIN}:{ENV_BIN}:{os.environ.get('PATH', '')}",
        "PYTHONPATH": str(session.content / "src"),
        "PYTHONUNBUFFERED": "1",
        # MLflow's job workers (for GenAI evaluation, which the workshop does
        # not use) hold about 2 GB between them while idle.
        "MLFLOW_SERVER_ENABLE_JOB_EXECUTION": "false",
        "AIRFLOW_HOME": str(session.state / "airflow"),
        "AIRFLOW__CORE__EXECUTOR": "LocalExecutor",
        "AIRFLOW__CORE__LOAD_EXAMPLES": "false",
        "AIRFLOW__CORE__DAGS_FOLDER": str(session.content / "dags"),
        "AIRFLOW__CORE__FERNET_KEY": credentials["fernet"],
        # One task at a time bounds the memory the background services use.
        "AIRFLOW__CORE__PARALLELISM": "1",
        "AIRFLOW__CORE__MAX_ACTIVE_RUNS_PER_DAG": "1",
        # The notebook server's login is the only gate; its owner administers
        # their own Airflow.
        "AIRFLOW__CORE__SIMPLE_AUTH_MANAGER_ALL_ADMINS": "true",
        "AIRFLOW__CORE__EXECUTION_API_SERVER_URL":
            f"http://127.0.0.1:{AIRFLOW_PORT}{session.airflow_path}/execution/",
        "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN": database_url(credentials, "airflow"),
        "AIRFLOW__API__BASE_URL": session.origin + session.airflow_path,
        "AIRFLOW__API__SECRET_KEY": credentials["api"],
        "AIRFLOW__API_AUTH__JWT_SECRET": credentials["jwt"],
        "AIRFLOW__DAG_PROCESSOR__PARSING_PROCESSES": "1",
    }


def services(session, credentials, socket_dir):
    """Every service in start order. PostgreSQL is first: the others need it.

    They stop in reverse. SIGINT is PostgreSQL's fast shutdown: it ends open
    connections and writes a checkpoint, where SIGTERM would wait for clients.
    """
    airflow = str(AIRFLOW_BIN / "airflow")
    return [
        Service("PostgreSQL", [
            str(ENV_BIN / "postgres"), "-D", str(session.state / "postgres"),
            "-h", "127.0.0.1", "-p", str(POSTGRES_PORT), "-k", socket_dir,
            "-c", "shared_buffers=64MB", "-c", "max_connections=40",
        ], signal.SIGINT),
        Service("MLflow", [
            str(ENV_BIN / "mlflow"), "server", "--host", "127.0.0.1",
            "--port", str(MLFLOW_PORT), "--workers", "1",
            "--static-prefix", session.mlflow_path,
            "--allowed-hosts", ",".join((f"127.0.0.1:{MLFLOW_PORT}", f"localhost:{MLFLOW_PORT}",
                                         urlsplit(session.origin).netloc)),
            # A browser's writes carry its Origin, which MLflow checks against
            # this list, separately from the hosts above. Loopback origins
            # are always allowed.
            "--cors-allowed-origins", session.origin,
            "--backend-store-uri", database_url(credentials, "mlflow"),
            "--artifacts-destination", str(session.state / "mlflow-artifacts"),
        ], signal.SIGTERM),
        Service("Airflow API", [
            airflow, "api-server", "--host", "127.0.0.1", "--port", str(AIRFLOW_PORT),
            "--workers", "1", "--proxy-headers",
        ], signal.SIGTERM),
        # The scheduler and triggerer would each serve task logs on every
        # interface for remote API servers. This one reads the files directly.
        Service("Airflow scheduler", [airflow, "scheduler", "--skip-serve-logs"], signal.SIGTERM),
        Service("Airflow DAG processor", [airflow, "dag-processor"], signal.SIGTERM),
        Service("Airflow triggerer", [airflow, "triggerer", "--skip-serve-logs"], signal.SIGTERM),
    ]


def load_credentials(state):
    """Secrets generated on the first start and kept with the data they protect."""
    file = state / "credentials.json"
    if not file.exists():
        new = file.with_suffix(".new")
        new.write_text(json.dumps({
            "postgres": secrets.token_hex(32),
            "jwt": secrets.token_hex(32),
            "api": secrets.token_hex(32),
            # A Fernet key: 32 random bytes, URL-safe base64.
            "fernet": base64.urlsafe_b64encode(secrets.token_bytes(32)).decode(),
        }))
        new.replace(file)
    return json.loads(file.read_text())


def create_cluster(pgdata, credentials):
    if (pgdata / "PG_VERSION").exists():
        return
    # Built beside its final place and moved in, so an interrupted start
    # leaves nothing that looks like a finished cluster.
    new = pgdata.with_name(pgdata.name + ".new")
    shutil.rmtree(new, ignore_errors=True)
    with tempfile.NamedTemporaryFile("w", prefix="ai-ready-pw-") as password:
        password.write(credentials["postgres"])
        password.flush()
        subprocess.run([
            str(ENV_BIN / "initdb"), "-D", str(new), "-U", POSTGRES_USER,
            "--encoding=UTF8", "--locale=C",
            "--auth-local=trust", "--auth-host=scram-sha-256", f"--pwfile={password.name}",
        ], check=True, stdout=subprocess.DEVNULL)
    new.rename(pgdata)


def remove_stale_lock(pgdata):
    """Drop the lock a killed container left behind.

    PostgreSQL refuses to start while the PID in postmaster.pid is alive. In
    a new container that PID is usually some other process, never the old
    server.
    """
    lock = pgdata / "postmaster.pid"
    try:
        pid = int(lock.read_text().split()[0])
    except (FileNotFoundError, IndexError, ValueError):
        return
    try:
        running = Path(f"/proc/{pid}/comm").read_text().strip() == "postgres"
    except OSError:
        running = False
    if not running:
        log("removing the PostgreSQL lock of a session that did not stop cleanly")
        lock.unlink()


def start(service, env, running):
    log(f"starting {service.name}")
    # Each service gets its own session, so a SIGTERM sent to the container's
    # process group reaches only this supervisor, which stops them in order.
    process = subprocess.Popen(service.argv, env=env, stdin=subprocess.DEVNULL,
                               start_new_session=True)
    running.append((service, process))


def check(running):
    for service, process in running:
        if process.poll() is not None:
            raise RuntimeError(f"{service.name} exited with status {process.returncode}")


def create_databases(credentials, running):
    import psycopg2
    from psycopg2 import sql

    for _ in range(120):
        check(running)
        try:
            connection = psycopg2.connect(
                host="127.0.0.1", port=POSTGRES_PORT, user=POSTGRES_USER,
                password=credentials["postgres"], dbname="postgres", connect_timeout=2)
            break
        except psycopg2.OperationalError:
            time.sleep(1)
    else:
        raise RuntimeError("PostgreSQL did not accept connections within 120 seconds")
    connection.autocommit = True
    with connection.cursor() as cursor:
        for database in DATABASES:
            cursor.execute("SELECT 1 FROM pg_database WHERE datname = %s", (database,))
            if cursor.fetchone() is None:
                cursor.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(database)))
    connection.close()


def prepare_airflow(session, env):
    airflow = str(AIRFLOW_BIN / "airflow")
    subprocess.run([airflow, "db", "migrate"], env=env, check=True, stdin=subprocess.DEVNULL)
    # The workshop's defaults are imported once, so later starts keep what the
    # user changed in the Airflow UI.
    imported = session.state / "airflow-variables-imported"
    if not imported.exists():
        subprocess.run([airflow, "variables", "import", str(UPSTREAM / "variables.json")],
                       env=env, check=True, stdin=subprocess.DEVNULL)
        imported.touch()


def serve(session, running):
    session.state.mkdir(exist_ok=True)
    credentials = load_credentials(session.state)
    pgdata = session.state / "postgres"
    create_cluster(pgdata, credentials)
    remove_stale_lock(pgdata)
    env = service_env(session, credentials)
    with tempfile.TemporaryDirectory(prefix="ai-ready-postgres-") as socket_dir:
        database, *dependents = services(session, credentials, socket_dir)
        try:
            start(database, env, running)
            create_databases(credentials, running)
            prepare_airflow(session, env)
            for service in dependents:
                start(service, env, running)
            log("services started")
            while True:
                check(running)
                time.sleep(1)
        finally:
            stop(running)


def stop(running):
    """Stop what depends on PostgreSQL first, then PostgreSQL."""
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    deadline = time.monotonic() + STOP_SECONDS
    for group, until in ((running[1:], deadline - POSTGRES_STOP_SECONDS), (running[:1], deadline)):
        for service, process in reversed(group):
            if process.poll() is None:
                os.killpg(process.pid, service.stop_signal)
        for service, process in group:
            try:
                process.wait(timeout=max(0.1, until - time.monotonic()))
            except subprocess.TimeoutExpired:
                log(f"{service.name} did not stop in time; killing it")
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
    log("services stopped")


def end_session(main_process):
    """End the notebook server too: a session without its services only confuses."""
    try:
        os.kill(main_process, signal.SIGTERM)
    except ProcessLookupError:
        pass
    except PermissionError:
        log("cannot stop the notebook server from here; restart the session to get the services back")


def run():
    # The start hook launched this from the shell that becomes the notebook
    # server (or sudo in front of it, when the container started as root).
    main_process = os.getppid()

    def on_signal(signum, _frame):
        raise Stop(signal.Signals(signum).name)

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)
    os.umask(0o077)
    try:
        serve(Session.from_environ(), [])
    except Stop as reason:
        log(f"stopped by {reason}")
        return 0
    except Exception as error:
        log(f"FAILED: {error}. Ending the session; the lines above say why.")
        end_session(main_process)
        return 1


def main(argv):
    if argv == ["run"]:
        return run()
    if argv == ["env"]:
        for name, value in notebook_env(Session.from_environ()).items():
            print(f"export {name}={shlex.quote(value)}")
        return 0
    sys.exit(__doc__)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
