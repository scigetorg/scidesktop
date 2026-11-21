# Slurm's part of the notebook server's configuration: when the server exits,
# it tells the queue's supervisor to stop and stays until it has.
#
# The container ends when the notebook server exits, and takes every process
# with it. Without this wait the daemons would be killed while they end
# running jobs. A container stop signals the supervisor too, and a second
# SIGTERM does nothing then; when the server exits on its own, this one is
# the only signal.
import atexit
import os
import signal
import time


def _stop_slurm(pid, seconds=45):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as cmdline:
            if b"slurm-session" not in cmdline.read():
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


# Set by the start hook (50-slurm.sh); removed here so kernels and terminals
# do not inherit it.
_supervisor = os.environ.pop("SCIDESKTOP_SLURM_SUPERVISOR_PID", "")
if _supervisor.isdigit():
    atexit.register(_stop_slurm, int(_supervisor))
