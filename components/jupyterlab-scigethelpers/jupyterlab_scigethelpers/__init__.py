"""JupyterLab server extension for scigethelpers."""

from .handlers import setup_handlers


def _jupyter_server_extension_points():
    return [{"module": "jupyterlab_scigethelpers"}]


def _load_jupyter_server_extension(server_app):
    """Register the scigethelpers API handlers without running probes at startup."""
    setup_handlers(server_app)
    server_app.log.info("jupyterlab_scigethelpers server extension loaded.")
