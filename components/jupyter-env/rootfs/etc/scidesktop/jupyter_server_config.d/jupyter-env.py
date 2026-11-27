# Re-enable @jupyterhub/jupyter-server-proxy in memory when a shared home
# carries legacy neurodesktop's user-level page_config.json disable (without
# mutating ~/.jupyter/labconfig/page_config.json on disk, and while preserving
# operator disables/locks at system, sys_prefix, app, JUPYTER_CONFIG_PATH, or
# installed extension metadata levels).
import json
import os
import stat

from jupyter_core import paths as jupyter_paths
from jupyter_server.services.config.manager import ConfigManager, recursive_update
from jupyterlab_server.config import get_federated_extensions, load_config

_SERVER_PROXY_EXT = "@jupyterhub/jupyter-server-proxy"


def _ext_enabled_in(mapping, ext):
    if isinstance(mapping, list):
        return ext in mapping
    if isinstance(mapping, dict):
        return bool(mapping.get(ext))
    return False


def _has_legacy_neurodesk_provenance(user_cfg):
    if "neurodeskSupporter" in user_cfg:
        return True
    home = os.environ.get("HOME") or ""
    if not home or not os.path.isabs(home):
        return False
    # Older neurodesktop homes (before neurodeskSupporter existed) created
    # ~/neurodesktop-storage (directory or symlink) or appended neurodesktop
    # hooks to ~/.bashrc.
    try:
        st_storage = os.lstat(os.path.join(home, "neurodesktop-storage")).st_mode
        if stat.S_ISDIR(st_storage) or stat.S_ISLNK(st_storage):
            return True
    except OSError:
        pass
    fd = -1
    try:
        fd = os.open(
            os.path.join(home, ".bashrc"),
            os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
        )
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            return False
        with os.fdopen(fd, "rb") as fh:
            fd = -1
            if st.st_size > 65536:
                fh.seek(-65536, os.SEEK_END)
            text = fh.read(65536).decode("utf-8", errors="ignore")
        return (
            "/opt/neurodesktop/environment_variables.sh" in text
            or "# Neurodesk bashrc additions" in text
        )
    except OSError:
        return False
    finally:
        if fd >= 0:
            try:
                os.close(fd)
            except OSError:
                pass


def _disabled_without_legacy_user_entry(handler, user_dir):
    """Evaluate JupyterLab's exact disable rollup without the legacy user entry."""
    user_norm = os.path.normpath(user_dir)
    user_real = os.path.realpath(user_dir)
    all_config_paths = jupyter_paths.jupyter_config_path()
    operator_dirs = [p for p in all_config_paths if os.path.normpath(p) != user_norm]
    extra_operator_dirs = [
        *jupyter_paths.ENV_CONFIG_PATH,
        *jupyter_paths.SYSTEM_CONFIG_PATH,
        *(p for p in os.environ.get("JUPYTER_CONFIG_PATH", "").split(os.pathsep) if p),
    ]
    # If the user config dir is a symlink or alias to any system, env, or
    # operator config directory, treat its settings as operator-controlled.
    if any(
        os.path.realpath(p) == user_real
        for p in (*operator_dirs, *extra_operator_dirs)
    ):
        return True

    app = getattr(handler, "extensionapp", None)
    app_settings_dir = getattr(app, "app_settings_dir", None)
    static_cfg = {}
    if app_settings_dir:
        for name in ("page_config.json5", "page_config.json"):
            path = os.path.join(app_settings_dir, name)
            if os.path.isfile(path) and os.path.getsize(path):
                data = load_config(path)
                for key in ("disabledExtensions", "lockedExtensions"):
                    if isinstance(data.get(key), list):
                        data[key] = {ext: True for ext in data[key]}
                recursive_update(static_cfg, data)
                break

    # Merge config layers in ConfigManager's exact back-to-front precedence,
    # subtracting only _SERVER_PROXY_EXT from the user layer's disabledExtensions.
    for path in all_config_paths[::-1]:
        layer = ConfigManager(
            read_config_path=[os.path.join(path, "labconfig")]
        ).get("page_config")
        if os.path.normpath(path) == user_norm:
            layer_disabled = layer.get("disabledExtensions")
            if isinstance(layer_disabled, dict):
                layer_disabled.pop(_SERVER_PROXY_EXT, None)
        recursive_update(static_cfg, layer)

    if _ext_enabled_in(static_cfg.get("lockedExtensions"), _SERVER_PROXY_EXT):
        return True

    static_disabled = static_cfg.get("disabledExtensions")
    if not isinstance(static_disabled, dict):
        static_disabled = {}

    if app is not None and hasattr(app, "labextensions_path"):
        labextensions_path = list(getattr(app, "extra_labextensions_path", [])) + list(
            app.labextensions_path
        )
    else:
        labextensions_path = jupyter_paths.jupyter_path("labextensions")

    # Mirror jupyterlab_server.config.get_page_config's extension-metadata rollup:
    # federated metadata takes precedence over source extensionMetadata by name,
    # and an extension's metadata is skipped only if static config disables it.
    disabled_by_extensions_all = {}
    for _, ext_data in get_federated_extensions(labextensions_path).items():
        jlab = ext_data.get("jupyterlab") or {}
        if "_build" not in jlab:
            continue
        if jlab.get("disabledExtensions"):
            disabled_by_extensions_all[ext_data["name"]] = jlab["disabledExtensions"]

    if app_settings_dir:
        pkg_path = os.path.join(
            os.path.dirname(app_settings_dir), "static", "package.json"
        )
        if os.path.isfile(pkg_path):
            try:
                with open(pkg_path, encoding="utf-8") as fh:
                    app_data = json.load(fh)
                ext_meta = app_data.get("jupyterlab", {}).get("extensionMetadata", {})
                for ext_name, ext_data in ext_meta.items():
                    if ext_name in disabled_by_extensions_all:
                        continue
                    if ext_data.get("disabledExtensions"):
                        disabled_by_extensions_all[ext_name] = ext_data[
                            "disabledExtensions"
                        ]
            except (OSError, ValueError):
                pass

    rollup_disabled = {}
    for name in sorted(disabled_by_extensions_all):
        if static_disabled.get(name) is True:
            continue
        for item in disabled_by_extensions_all[name]:
            rollup_disabled[item] = True

    rollup_disabled.update(static_disabled)
    return bool(rollup_disabled.get(_SERVER_PROXY_EXT))


def _scidesktop_page_config_hook(handler, page_config):
    disabled = page_config.get("disabledExtensions")
    if (
        not isinstance(disabled, list)
        or _SERVER_PROXY_EXT not in disabled
        or os.environ.get("SCIDESKTOP_KEEP_DISABLED_SERVER_PROXY") == "1"
        or _ext_enabled_in(page_config.get("lockedExtensions"), _SERVER_PROXY_EXT)
    ):
        return page_config
    user_dir = os.path.normpath(jupyter_paths.jupyter_config_dir())
    user_cfg = ConfigManager(
        read_config_path=[os.path.join(user_dir, "labconfig")]
    ).get("page_config")
    if (
        _ext_enabled_in(user_cfg.get("disabledExtensions"), _SERVER_PROXY_EXT)
        and _has_legacy_neurodesk_provenance(user_cfg)
        and not _disabled_without_legacy_user_entry(handler, user_dir)
    ):
        page_config["disabledExtensions"] = [
            ext for ext in disabled if ext != _SERVER_PROXY_EXT
        ]
    return page_config


c.ServerApp.tornado_settings.update({"page_config_hook": _scidesktop_page_config_hook})  # noqa: F821
