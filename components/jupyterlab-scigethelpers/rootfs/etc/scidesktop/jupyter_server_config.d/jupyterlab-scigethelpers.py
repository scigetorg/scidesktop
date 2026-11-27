# Session Helpers panel's part of the notebook server's configuration: its
# server extension, which serves the authenticated JSON API at
# <session URL>/scigethelpers/api/* behind the notebook server's login.
# The JupyterLab extension itself is found under
# /usr/local/share/jupyter/labextensions.
import sys

# The extension is imported from the component's folder without a PYTHONPATH
# that kernels would inherit.
_lib = "/opt/jupyterlab-scigethelpers/lib"
if _lib not in sys.path:
    sys.path.append(_lib)

c.ServerApp.jpserver_extensions.update({"jupyterlab_scigethelpers": True})  # noqa: F821
