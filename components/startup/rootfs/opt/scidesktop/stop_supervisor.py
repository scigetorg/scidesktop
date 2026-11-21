"""Stop a background session supervisor cleanly when the notebook server exits.

Shared by components that run background daemons beside Jupyter (such as slurm
and ai-ready). The container ends when the notebook server exits, so waiting
here lets supervisors shut down daemons (e.g. slurmd, PostgreSQL) cleanly on
both container stop and Jupyter's own shutdown path.
"""

import atexit
import os
import signal
import time


def stop_supervisor(pid, marker, seconds=30):
    """Send SIGTERM to *pid* if its cmdline still contains *marker*, and wait."""
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as cmdline:
            if marker.encode() not in cmdline.read():
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


def register_supervisor_shutdown(env_var, marker, seconds=30):
    """Pop *env_var* so children do not inherit it, and stop it at exit."""
    pid = os.environ.pop(env_var, "")
    if pid.isdigit():
        atexit.register(stop_supervisor, int(pid), marker, seconds)
