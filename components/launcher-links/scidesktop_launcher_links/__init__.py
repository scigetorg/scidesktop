"""Jupyter Server extension exposing operator-configured external launcher links."""

from .handlers import setup_handlers


def _jupyter_server_extension_points():
    return [{"module": "scidesktop_launcher_links"}]


def _load_jupyter_server_extension(server_app):
    setup_handlers(server_app.web_app, log=server_app.log)
