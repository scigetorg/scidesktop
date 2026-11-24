"""Tornado handlers for serving the standalone Neuroglancer client."""

import os
import re

from jupyter_server.base.handlers import JupyterHandler
from jupyter_server.utils import url_path_join
from tornado.web import StaticFileHandler, authenticated

HERE = os.path.dirname(__file__)
STATIC_DIR = os.path.join(HERE, "static", "neuroglancer")


class NeuroglancerRedirectHandler(JupyterHandler):
    """Redirect /neuroglancer to /neuroglancer/ so relative asset URLs resolve."""

    @authenticated
    def get(self):
        target = url_path_join(self.base_url, "neuroglancer/")
        if self.request.query:
            target = f"{target}?{self.request.query}"
        self.redirect(target)


class NeuroglancerStaticHandler(JupyterHandler, StaticFileHandler):
    """Authenticated, packaged Neuroglancer client assets, never user workspace files."""

    def check_xsrf_cookie(self):
        # Module scripts, Web Workers and WASM fetches use CORS/same-origin mode
        # without an X-XSRFToken header; HubOAuth otherwise rejects their
        # session cookies. Fetch Metadata is browser-controlled, and
        # authentication still runs on every request.
        if (
            self.request.method in {"GET", "HEAD"}
            and self.request.headers.get("Sec-Fetch-Site") == "same-origin"
        ):
            return
        return super().check_xsrf_cookie()

    def get_content_type(self):
        if self.absolute_path:
            if self.absolute_path.endswith(".wasm"):
                return "application/wasm"
            if self.absolute_path.endswith(".js"):
                return "application/javascript"
            if self.absolute_path.endswith(".css"):
                return "text/css"
        return super().get_content_type()

    @authenticated
    async def get(self, path, include_body=True):
        await super().get(path, include_body)

    @authenticated
    async def head(self, path):
        await self.get(path, include_body=False)


def setup_handlers(web_app):
    """Register the /neuroglancer/ static file handler."""
    base_url = web_app.settings.get("base_url", "/")
    base_route = re.escape(url_path_join(base_url, "neuroglancer"))
    web_app.add_handlers(
        r".*",
        [
            (base_route + r"$", NeuroglancerRedirectHandler),
            (
                base_route + r"/(.*)",
                NeuroglancerStaticHandler,
                {"path": STATIC_DIR, "default_filename": "index.html"},
            ),
        ],
    )
