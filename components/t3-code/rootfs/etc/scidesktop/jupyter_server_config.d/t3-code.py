# T3 Code's part of the notebook server's configuration: the scigent.ai tile
# and the proxy entry behind it (/opt/t3-code/lib/t3_code_proxy.py).
import atexit
import sys

# Jupyter imports the entry from here without a PYTHONPATH that kernels
# would inherit.
_lib = "/opt/t3-code/lib"
if _lib not in sys.path:
    sys.path.append(_lib)
import t3_code_proxy  # noqa: E402

c.ServerProxy.servers.update({t3_code_proxy.ROUTE: t3_code_proxy.server_entry()})  # noqa: F821
t3_code_proxy.redact_tickets()
atexit.register(t3_code_proxy.stop_server)
