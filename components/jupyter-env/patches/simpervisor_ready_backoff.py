"""Cap simpervisor's readiness poll interval at 0.1 s.

jupyter-server-proxy starts the desktop (Selkies) through simpervisor, which
polls whether it is ready at doubling intervals: 0.01, 0.02 ... s, so checks
land at about 0.63, 1.27, 2.55, 5.1, 10.2 and 20.5 s after launch. The desktop
is reported ready at the first check after it actually is, so a desktop ready
at 1.3 s shows at 2.55 s, and a slow node can round up to 5 or 10 s. Capping
the interval at 0.1 s reports it within 0.1 s of being ready, for at most ten
local connection attempts a second while a server starts.

It applies only to the exact upstream line and reports when that line is not
found, so a changed upstream release is left alone.

    python simpervisor_ready_backoff.py   # run with the environment's interpreter
"""
import importlib.util
import sys

spec = importlib.util.find_spec("simpervisor.process")
if spec is None:
    print("simpervisor not installed; nothing to patch")
    sys.exit(0)
path = spec.origin
src = open(path).read()

OLD = "            wait_time = 2 * wait_time\n"
NEW = "            wait_time = min(2 * wait_time, 0.1)  # scidesktop: capped poll\n"

if NEW in src:
    print(f"{path}: already patched")
    sys.exit(0)
if src.count(OLD) != 1:
    print(f"{path}: upstream text changed; patch not applied")
    sys.exit(0)
open(path, "w").write(src.replace(OLD, NEW))

# The patched module must still import, and carry the cap.
import simpervisor.process  # noqa: E402

assert "min(2 * wait_time, 0.1)" in open(simpervisor.process.__file__).read()
print(f"{path}: readiness poll capped at 0.1 s")
