# Neuroglancer's part of the notebook server's configuration: its server
# extension, which serves the standalone Neuroglancer viewer at
# <session URL>/neuroglancer/ behind the notebook server's login. The
# JupyterLab extension itself is found under
# /usr/local/share/jupyter/labextensions.
import sys

# The extension is imported from the component's folder without a PYTHONPATH
# that kernels would inherit.
_lib = "/opt/jupyterlab-neuroglancer/lib"
if _lib not in sys.path:
    sys.path.append(_lib)

c.ServerApp.jpserver_extensions.update({"jupyterlab_neuroglancer": True})  # noqa: F821
