# FreeBrowse's part of the notebook server's configuration: its server
# extension, which serves the viewer at <session URL>/freebrowse/ behind the
# notebook server's login. The JupyterLab extension itself is found under
# /usr/local/share/jupyter/labextensions.
import sys

# The extension is imported from the component's folder without a PYTHONPATH
# that kernels would inherit.
_lib = "/opt/jupyterlab-freebrowse/lib"
if _lib not in sys.path:
    sys.path.append(_lib)

c.ServerApp.jpserver_extensions.update({"jupyterlab_freebrowse": True})  # noqa: F821
