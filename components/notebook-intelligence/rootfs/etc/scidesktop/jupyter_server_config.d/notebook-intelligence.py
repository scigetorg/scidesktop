# Notebook Intelligence's part of the notebook server's configuration:
# loads the server extension from /opt/notebook-intelligence/lib without
# adding its dependencies to notebook kernels.
import sys

_lib = "/opt/notebook-intelligence/lib"
if _lib not in sys.path:
    sys.path.append(_lib)

c.ServerApp.jpserver_extensions.update({"notebook_intelligence": True})  # noqa: F821
