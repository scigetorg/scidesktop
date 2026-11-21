# AI Ready's part of the notebook server's configuration. Images that copy the
# ai-ready component put this folder on JUPYTER_CONFIG_PATH, so it is read
# after the base's files and adds to them.
import atexit
import os
import signal
import sys
import time

# The dashboard handler and the service definitions; Jupyter imports them
# from here without a PYTHONPATH that kernels would inherit.
_lib = "/opt/ai-ready/lib"
if _lib not in sys.path:
    sys.path.append(_lib)
from ai_ready_services import AIRFLOW_PORT, MLFLOW_PORT  # noqa: E402

# Airflow and MLflow listen on loopback only. The proxy checks the notebook
# server's login before it forwards a request, Airflow's admin UI included.
# update() adds to the entries of other components (the desktop).
c.ServerProxy.servers.update({  # noqa: F821
    name: {
        "port": port,
        # Both serve under the session's own path, so the proxy keeps it.
        "absolute_url": True,
        "launcher_entry": {
            "enabled": True,
            "title": title,
            "icon_path": f"/opt/ai-ready/upstream/icons/{name}.svg",
            "category": "AI Ready",
        },
    }
    for name, title, port in (("airflow", "Airflow", AIRFLOW_PORT), ("mlflow", "MLflow", MLFLOW_PORT))
})
c.ServerApp.extra_services.append("ai_ready_dashboard")  # noqa: F821
c.ServerApp.extra_template_paths.append(_lib)  # noqa: F821
c.ServerApp.default_url = "/ai-ready/"  # noqa: F821
c.LabApp.default_url = "/ai-ready/"  # noqa: F821


def _stop_services(pid, seconds=30):
    """Tell the supervisor to stop, and stay until it has stopped PostgreSQL.

    The container ends when the notebook server exits, and takes every
    process with it. Without this wait PostgreSQL would be killed partway
    through its shutdown. A container stop signals the supervisor too, and a
    second SIGTERM does nothing then; when the server exits on its own (its
    shutdown API, a signal to it alone), this one is the only signal.
    """
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as cmdline:
            if b"ai_ready_services.py" not in cmdline.read():
                return
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            with open(f"/proc/{pid}/stat") as stat:
                state = stat.read().rpartition(")")[2].split()[0]
        except OSError:
            return
        if state == "Z":
            return
        time.sleep(0.1)


# Set by the start hook (40-ai-ready.sh); removed here so kernels and
# terminals do not inherit it.
_supervisor = os.environ.pop("AI_READY_SUPERVISOR_PID", "")
if _supervisor.isdigit():
    atexit.register(_stop_services, int(_supervisor))
