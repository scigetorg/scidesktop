# The NiiVue viewer's part of the notebook server's configuration: its server
# extension, which serves the viewer's own files to JupyterLab. The JupyterLab
# extension itself is found under /usr/local/share/jupyter/labextensions.
import sys

# The extension is imported from the component's folder without a PYTHONPATH
# that kernels would inherit.
_lib = "/opt/jupyterlab-niivue/lib"
if _lib not in sys.path:
    sys.path.append(_lib)

c.ServerApp.jpserver_extensions.update({"jupyterlab_niivue": True})  # noqa: F821
