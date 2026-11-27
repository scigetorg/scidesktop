# Keep @jupyterhub/jupyter-server-proxy enabled in rendered Lab page_config
# even when a legacy Neurodesktop session on a shared home disabled it in
# ~/.jupyter/labconfig/page_config.json, without mutating the shared file.
import sys

if "/opt/scidesktop/jupyter-env" not in sys.path:
    sys.path.insert(0, "/opt/scidesktop/jupyter-env")
c.ServerApp.jpserver_extensions.update({"scidesktop_page_config": True})  # noqa: F821
