"""JupyterLab extension for the Neuroglancer volumetric and OME-Zarr viewer."""

from .handlers import setup_handlers


def _jupyter_labextension_paths():
    return [{"src": "labextension", "dest": "jupyterlab-neuroglancer"}]


def _jupyter_server_extension_points():
    return [{"module": "jupyterlab_neuroglancer"}]


def _load_jupyter_server_extension(server_app):
    """Register the Neuroglancer static file handler."""
    setup_handlers(server_app.web_app)
    server_app.log.info("jupyterlab_neuroglancer server extension loaded.")
