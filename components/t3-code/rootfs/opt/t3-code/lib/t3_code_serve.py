"""Start one user's T3 Code server for Jupyter Server Proxy.

    t3_code_serve.py <port>

Prepares T3's data directory, then becomes the server, so the proxy's signals
reach T3 itself. T3 listens on loopback only. Everything it keeps is in its
data directory, ~/.t3 unless T3CODE_HOME says otherwise.
"""

import copy
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from t3_code_proxy import SESSION_FILE, base_dir

T3 = "/opt/t3-code/app/t3"
# Image defaults for T3's settings.json: every *.json here, in name order.
SETTINGS_DEFAULTS = Path("/etc/scidesktop/t3-code/settings.d")
# Image defaults for the server's environment: every *.json here, in name
# order, each an object of variable names and values. A variable the
# deployment set is kept.
ENVIRONMENT_DEFAULTS = Path("/etc/scidesktop/t3-code/environment.d")
# The proxy's session outlives any notebook server; each start replaces it.
SESSION_TTL = "3650d"


def log(message):
    print(f"[t3-code] {message}", file=sys.stderr, flush=True)


def write_private(file, content):
    """Replace `file` in one step, readable by the user only."""
    descriptor, temporary = tempfile.mkstemp(prefix=f".{file.name}-", dir=file.parent)
    try:
        with os.fdopen(descriptor, "w") as stream:
            stream.write(content)
        os.replace(temporary, file)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def add_defaults(settings, defaults):
    """Fill in what `settings` does not say; True if anything was added.

    A value the user (or T3 on their behalf) has set is never changed, at any
    depth.
    """
    added = False
    for key, value in defaults.items():
        if key not in settings:
            settings[key] = copy.deepcopy(value)
            added = True
        elif isinstance(settings[key], dict) and isinstance(value, dict):
            added = add_defaults(settings[key], value) or added
    return added


def _provider_instance_user_owned(instance_id, seed, instances, providers):
    """True when the user already owns this provider instance or driver."""
    driver = seed.get("driver")
    if instance_id in instances:
        return True
    if any(instance.get("driver") == driver for instance in instances.values()):
        return True
    if driver not in providers:
        return False
    legacy = providers[driver]
    # T3 writes {"enabled": false} under providers.<driver> for drivers it ships
    # disabled by default; treat that bookkeeping (and an empty dict) as inert
    # when a seed explicitly enables the driver.
    if seed.get("enabled") is True and legacy in ({}, {"enabled": False}):
        return False
    # Earlier images wrote only {"binaryPath": ...} under providers.codex.
    seed_config = seed.get("config")
    if (
        driver == "codex"
        and isinstance(seed_config, dict)
        and isinstance(seed_config.get("binaryPath"), str)
        and legacy == {"binaryPath": seed_config["binaryPath"]}
    ):
        return False
    return True


def _prepare_provider_instance(instance_id, seed, instances, providers):
    """Return an instance dict to write for `instance_id`, or None to skip."""
    if not isinstance(seed, dict) or not isinstance(seed.get("driver"), str):
        return None
    driver = seed["driver"]
    seed_config = seed.get("config")
    # Upgrade an earlier bundled Codex instance that only recorded binaryPath in
    # place so T3 0.1.5 probes the installed CLI instead of switching to managed
    # mode, while keeping explicit setup modes and custom instances untouched.
    if (
        isinstance(seed_config, dict)
        and isinstance(seed_config.get("setupMode"), str)
        and isinstance(instances.get(instance_id), dict)
    ):
        current = instances[instance_id]
        base_config = {k: v for k, v in seed_config.items() if k != "setupMode"}
        previous = {"driver": driver, "config": base_config}
        if current.get("enabled") is True:
            previous["enabled"] = True
        if current == previous:
            return {**current, **copy.deepcopy(seed)}
    if _provider_instance_user_owned(instance_id, seed, instances, providers):
        return None
    return copy.deepcopy(seed)


def apply_provider_instance_defaults(settings, seeds):
    """Seed `providerInstances` entries without overwriting user configuration."""
    if not isinstance(seeds, dict):
        return False
    instances = settings.get("providerInstances", {})
    providers = settings.get("providers", {})
    if not (
        isinstance(instances, dict)
        and isinstance(providers, dict)
        and all(isinstance(instance, dict) for instance in instances.values())
    ):
        return False
    seeded = {}
    for instance_id, seed in seeds.items():
        prepared = _prepare_provider_instance(instance_id, seed, instances, providers)
        if prepared is not None:
            seeded[instance_id] = prepared
    if not seeded:
        return False
    settings["providerInstances"] = {**instances, **seeded}
    return True


def apply_settings_defaults(base, defaults_dir=SETTINGS_DEFAULTS):
    base.mkdir(mode=0o700, parents=True, exist_ok=True)
    userdata = base / "userdata"
    userdata.mkdir(mode=0o700, exist_ok=True)
    file = userdata / "settings.json"
    try:
        settings = json.loads(file.read_text())
    except FileNotFoundError:
        settings = {}
    except (ValueError, UnicodeError):
        return  # T3 reports a settings file it cannot read; do not replace it.
    if not isinstance(settings, dict):
        return
    added = False
    for defaults_file in sorted(defaults_dir.glob("*.json")):
        try:
            defaults = json.loads(defaults_file.read_text())
        except (OSError, ValueError, UnicodeError) as error:
            log(f"ignoring {defaults_file}: {error}")
            continue
        if isinstance(defaults, dict):
            top_level = {k: v for k, v in defaults.items() if k != "providerInstances"}
            added = add_defaults(settings, top_level) or added
            if "providerInstances" in defaults:
                added = apply_provider_instance_defaults(
                    settings, defaults["providerInstances"]
                ) or added
    if added:
        write_private(file, json.dumps(settings, indent=2) + "\n")


def t3(base, env, *arguments):
    return subprocess.run([T3, *arguments, "--base-dir", str(base)], env=env, check=True,
                          stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)


def issue_proxy_session(base, env):
    """Give the proxy a T3 session of its own, replacing the previous one."""
    file = base / SESSION_FILE
    try:
        previous = json.loads(file.read_text())["sessionId"]
    except (OSError, ValueError, KeyError):
        previous = None
    session = json.loads(t3(base, env, "auth", "session", "issue", "--label", "Jupyter proxy",
                            "--ttl", SESSION_TTL, "--json").stdout)
    write_private(file, json.dumps({"sessionId": session["sessionId"], "token": session["token"]}))
    if previous:
        try:
            t3(base, env, "auth", "session", "revoke", previous)
        except (subprocess.SubprocessError, OSError):
            log("could not revoke the previous proxy session; `t3 auth session list` shows it")


def environment_defaults(defaults_dir=ENVIRONMENT_DEFAULTS):
    defaults = {}
    for file in sorted(defaults_dir.glob("*.json")):
        try:
            values = json.loads(file.read_text())
        except (OSError, ValueError, UnicodeError) as error:
            log(f"ignoring {file}: {error}")
            continue
        if isinstance(values, dict):
            defaults.update({name: value for name, value in values.items()
                             if isinstance(name, str) and isinstance(value, str)})
    return defaults


def server_environment(base, environ=os.environ, defaults_dir=ENVIRONMENT_DEFAULTS):
    env = dict(environ)
    for name, value in environment_defaults(defaults_dir).items():
        env.setdefault(name, value)
    env.update({
        "T3CODE_HOME": str(base),
        "T3CODE_NO_BROWSER": "true",
        # The user chooses their projects; the home folder is not one.
        "T3CODE_AUTO_BOOTSTRAP_PROJECT_FROM_CWD": "false",
    })
    # Quiet and private unless the deployment says otherwise.
    for name, value in (
        ("T3CODE_LOG_LEVEL", "Warn"),
        ("T3CODE_TRACE_MIN_LEVEL", "Warn"),
        ("T3CODE_TRACE_TIMING_ENABLED", "false"),
        ("T3CODE_TRACE_FILE", "/dev/null"),
        ("T3CODE_TELEMETRY_ENABLED", "false"),
    ):
        env.setdefault(name, value)
    # The command line below decides where T3 listens.
    for name in ("T3CODE_HOST", "T3CODE_PORT", "T3CODE_LAN"):
        env.pop(name, None)
    # T3 Code's Antigravity sign-in helper expects a `node` binary on T3's PATH;
    # reuse code-server's Node without adding node/npm to user shells.
    if os.access("/opt/code-server/lib/node", os.X_OK):
        path_entries = [entry for entry in env.get("PATH", "").split(":") if entry]
        if "/opt/code-server/lib" not in path_entries:
            env["PATH"] = ":".join([*path_entries, "/opt/code-server/lib"])
    return env


def main(argv):
    if len(argv) != 1 or not argv[0].isdigit():
        sys.exit(__doc__)
    if os.geteuid() == 0:
        sys.exit("[t3-code] T3 Code runs as the notebook user, not as root")
    port = argv[0]
    base = base_dir()
    base.mkdir(mode=0o700, parents=True, exist_ok=True)
    env = server_environment(base)
    workdir = os.environ.get("T3_CODE_WORKDIR") or str(Path.home())
    apply_settings_defaults(base)
    issue_proxy_session(base, env)
    # T3 prints a pairing token and its QR code when it starts. They are not
    # for the notebook server's log; warnings and errors on stderr are.
    os.dup2(os.open(os.devnull, os.O_WRONLY), 1)
    os.chdir(workdir)
    os.execve(T3, [T3, "serve", "--mode", "web", "--no-browser", "--host", "127.0.0.1",
                   "--port", port, "--base-dir", str(base), workdir], env)


if __name__ == "__main__":
    main(sys.argv[1:])
