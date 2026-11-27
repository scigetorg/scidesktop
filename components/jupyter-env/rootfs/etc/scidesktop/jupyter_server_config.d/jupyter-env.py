# Re-enable @jupyterhub/jupyter-server-proxy in memory when a shared home
# carries legacy neurodesktop's user-level page_config.json disable (without
# mutating ~/.jupyter/labconfig/page_config.json on disk, and while preserving
# operator disables/locks at system, sys_prefix, app, or JUPYTER_CONFIG_PATH
# levels).
import os
import stat

from jupyter_core.paths import jupyter_config_dir, jupyter_config_path
from jupyter_server.services.config.manager import ConfigManager, recursive_update
from jupyterlab_server.config import load_config

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


def _operator_disables_or_locks(handler, user_dir):
    non_user_cfg = {}
    app_settings_dir = getattr(getattr(handler, "extensionapp", None), "app_settings_dir", None)
    if app_settings_dir:
        for name in ("page_config.json5", "page_config.json"):
            path = os.path.join(app_settings_dir, name)
            if os.path.isfile(path) and os.path.getsize(path):
                data = load_config(path)
                for key in ("disabledExtensions", "lockedExtensions"):
                    if isinstance(data.get(key), list):
                        data[key] = {ext: True for ext in data[key]}
                recursive_update(non_user_cfg, data)
                break
    user_real = os.path.realpath(user_dir)
    non_user_paths = [
        os.path.join(p, "labconfig")
        for p in jupyter_config_path()
        if os.path.realpath(p) != user_real
    ]
    if non_user_paths:
        recursive_update(
            non_user_cfg,
            ConfigManager(read_config_path=non_user_paths).get("page_config"),
        )
    return _ext_enabled_in(non_user_cfg.get("disabledExtensions"), _SERVER_PROXY_EXT) or (
        _ext_enabled_in(non_user_cfg.get("lockedExtensions"), _SERVER_PROXY_EXT)
    )


def _scidesktop_page_config_hook(handler, page_config):
    disabled = page_config.get("disabledExtensions")
    if (
        not isinstance(disabled, list)
        or _SERVER_PROXY_EXT not in disabled
        or os.environ.get("SCIDESKTOP_KEEP_DISABLED_SERVER_PROXY") == "1"
        or _ext_enabled_in(page_config.get("lockedExtensions"), _SERVER_PROXY_EXT)
    ):
        return page_config
    user_dir = os.path.normpath(jupyter_config_dir())
    user_cfg = ConfigManager(
        read_config_path=[os.path.join(user_dir, "labconfig")]
    ).get("page_config")
    if (
        _ext_enabled_in(user_cfg.get("disabledExtensions"), _SERVER_PROXY_EXT)
        and _has_legacy_neurodesk_provenance(user_cfg)
        and not _operator_disables_or_locks(handler, user_dir)
    ):
        page_config["disabledExtensions"] = [
            ext for ext in disabled if ext != _SERVER_PROXY_EXT
        ]
    return page_config


c.ServerApp.tornado_settings.update({"page_config_hook": _scidesktop_page_config_hook})  # noqa: F821
