# Slurm's part of the notebook server's configuration: when the server exits,
# it tells the queue's supervisor to stop and stays until it has.
import sys

if "/opt/scidesktop" not in sys.path:
    sys.path.append("/opt/scidesktop")
from stop_supervisor import register_supervisor_shutdown  # noqa: E402

# Set by the start hook (50-slurm.sh); removed here so kernels and terminals
# do not inherit it.
register_supervisor_shutdown("SCIDESKTOP_SLURM_SUPERVISOR_PID", "slurm-session", seconds=45)
