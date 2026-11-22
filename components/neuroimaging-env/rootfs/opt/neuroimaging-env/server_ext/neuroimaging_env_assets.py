"""Serve the patched ipyniivue shared frontend bundle behind Jupyter's login."""

from pathlib import Path
import tornado.web
from jupyter_server.base.handlers import JupyterHandler
from jupyter_server.utils import url_path_join

STATIC_DIR = Path("/opt/neuroimaging-env/static")


class IpyniivueAssetHandler(JupyterHandler):
    @tornado.web.authenticated
    def get(self, filename: str) -> None:
        target = (STATIC_DIR / filename).resolve()
        if target.parent != STATIC_DIR.resolve() or not target.is_file():
            raise tornado.web.HTTPError(404)
        self.set_header("Content-Type", "application/javascript; charset=utf-8")
        self.set_header("Cache-Control", "public, max-age=31536000, immutable")
        self.finish(target.read_bytes())


def _jupyter_server_extension_points():
    return [{"module": "neuroimaging_env_assets"}]


def _load_jupyter_server_extension(server_app):
    base_url = server_app.web_app.settings["base_url"]
    route = url_path_join(
        base_url,
        "neuroimaging-ipyniivue",
        r"(scidesktop-ipyniivue\.[0-9a-f]{20}\.js)",
    )
    server_app.web_app.add_handlers(".*$", [(route, IpyniivueAssetHandler)])
