# jupyterlab-slurm's part of the notebook server's configuration: its server
# extension, which exposes the Slurm queue endpoints behind the notebook
# server's login. The JupyterLab extension itself is linked under
# /usr/local/share/jupyter/labextensions.
import sys

_lib = "/opt/jupyterlab-slurm/lib"
if _lib not in sys.path:
    sys.path.append(_lib)

c.ServerApp.jpserver_extensions.update({"jupyterlab_slurm": True})  # noqa: F821
