# launcher-links' part of the notebook server's configuration: serves
# operator-configured external launcher tiles (such as WEBKNOSSOS via
# SCIDESKTOP_WEBKNOSSOS_URL or SCIDESKTOP_LAUNCHER_LINKS) behind the notebook
# server's login. The JupyterLab extension is linked under
# /usr/local/share/jupyter/labextensions.
import sys

_lib = "/opt/launcher-links/lib"
if _lib not in sys.path:
    sys.path.append(_lib)

c.ServerApp.jpserver_extensions.update({"scidesktop_launcher_links": True})  # noqa: F821
