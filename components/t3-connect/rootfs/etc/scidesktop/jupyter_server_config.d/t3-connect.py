# T3 Connect's part of the notebook server's configuration: the page and API
# at <session URL>/t3-connect/ that set up remote access to this session's
# T3 Code (/opt/t3-connect/lib/t3_connect.py). Nothing starts until the user
# asks there.
import sys

# The extension is imported from the component's folder, and T3 Code's own
# modules from its, without a PYTHONPATH that kernels would inherit.
for _lib in ("/opt/t3-code/lib", "/opt/t3-connect/lib"):
    if _lib not in sys.path:
        sys.path.append(_lib)

c.ServerApp.jpserver_extensions.update({"t3_connect": True})  # noqa: F821
