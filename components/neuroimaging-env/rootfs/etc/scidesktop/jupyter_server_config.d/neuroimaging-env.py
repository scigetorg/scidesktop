# neuroimaging-env's part of the notebook server's configuration: serves the
# shared ipyniivue frontend bundle behind Jupyter's login without writing into
# /opt/conda.
import sys

_ext = "/opt/neuroimaging-env/server_ext"
if _ext not in sys.path:
    sys.path.append(_ext)

c.ServerApp.jpserver_extensions.update({"neuroimaging_env_assets": True})  # noqa: F821
