"""SciDesktop Jupyter Server runtime hooks.

1. Keep `@jupyterhub/jupyter-server-proxy` enabled in rendered Lab `page_config`
   when a legacy Neurodesktop session on a shared home wrote
   `"@jupyterhub/jupyter-server-proxy": true` into
   `~/.jupyter/labconfig/page_config.json`, without mutating the shared file
   and while preserving operator disables/locks (at app, system, sys_prefix,
   JUPYTER_CONFIG_PATH, aliased config dir, or extension-metadata levels),
   deliberate non-legacy user disables, and `SCIDESKTOP_KEEP_DISABLED_SERVER_PROXY=1`.
   Chains after JupyterHub's own `page_config_hook` (Jupyter Server loads
   extensions in alphabetical order, so `scidesktop_page_config` loads after
   `jupyterhub`).

2. Keep `jupyterlmod`'s in-memory `avail_cache` synchronized with on-disk
   `MODULEPATH` updates (such as background `sciget refresh` /
   `cvmfs-domain-modules` sync or `sciget install` after the server starts).
"""

import asyncio
import json
import os
import stat

from jupyter_core import paths as jupyter_paths
from jupyter_server.services.config.manager import ConfigManager, recursive_update
from jupyterlab_server.config import get_federated_extensions, load_config

_REQUIRED_EXTENSION = "@jupyterhub/jupyter-server-proxy"
_CVMFS_SYNC_BIN = "/opt/scidesktop/cvmfs-domain-modules"


def _jupyter_server_extension_points():
    return [{"module": "scidesktop_page_config"}]


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
                # Mirror jupyterlab_server.config.get_page_config: every key in
                # app-level disabledExtensions becomes True (even dict values of False).
                if "disabledExtensions" in data:
                    data["disabledExtensions"] = {
                        ext: True for ext in data["disabledExtensions"]
                    }
                if isinstance(data.get("lockedExtensions"), list):
                    data["lockedExtensions"] = {
                        ext: True for ext in data["lockedExtensions"]
                    }
                recursive_update(static_cfg, data)
                break

    # Merge config layers in ConfigManager's exact back-to-front precedence,
    # subtracting only _REQUIRED_EXTENSION from the user layer's disabledExtensions.
    for path in all_config_paths[::-1]:
        layer = ConfigManager(
            read_config_path=[os.path.join(path, "labconfig")]
        ).get("page_config")
        if os.path.normpath(path) == user_norm:
            layer_disabled = layer.get("disabledExtensions")
            if isinstance(layer_disabled, dict):
                layer_disabled.pop(_REQUIRED_EXTENSION, None)
        recursive_update(static_cfg, layer)

    if _ext_enabled_in(static_cfg.get("lockedExtensions"), _REQUIRED_EXTENSION):
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
    return bool(rollup_disabled.get(_REQUIRED_EXTENSION))


def _modulepath_fingerprint() -> tuple:
    """Return a cheap stat fingerprint of local MODULEPATH dirs and CVMFS stamps."""
    entries = []
    mp = os.environ.get("MODULEPATH", "")
    seen_state_dirs: set[str] = set()
    for raw_dir in mp.split(os.pathsep):
        d = raw_dir.strip()
        if not d:
            continue
        try:
            st = os.stat(d)
            entries.append((d, st.st_mtime_ns, st.st_ctime_ns))
        except OSError:
            entries.append((d, None, None))
            continue

        # For local (non-CVMFS) directories, include child directory mtimes so
        # newly installed or synced tool versions inside existing tool folders
        # also invalidate the cache.
        if not d.startswith("/cvmfs/"):
            try:
                with os.scandir(d) as it:
                    children = []
                    for child in it:
                        try:
                            cst = child.stat(follow_symlinks=False)
                            children.append((child.name, cst.st_mtime_ns))
                        except OSError:
                            continue
                    children.sort()
                    entries.append((d, tuple(children)))
            except OSError:
                pass

            # Check companion cvmfs-domain-modules stamp file if present:
            # <base>/<arch>-<root_hash>/<cat>-<cat_hash> -> <base>/.state/<arch>-<root_hash>/<cat>-<cat_hash>.stamp
            parent = os.path.dirname(d)
            grandparent = os.path.dirname(parent)
            state_dir = os.path.join(grandparent, ".state", os.path.basename(parent))
            stamp = os.path.join(state_dir, f"{os.path.basename(d)}.stamp")
            if stamp not in seen_state_dirs:
                seen_state_dirs.add(stamp)
                try:
                    sst = os.stat(stamp)
                    entries.append((stamp, sst.st_mtime_ns, sst.st_size))
                except OSError:
                    entries.append((stamp, None, None))
    return tuple(entries)


def _install_lmod_cache_sync() -> None:
    try:
        import jupyterlmod.handler as lmod_handler
    except Exception:
        return
    mod_api = getattr(lmod_handler, "MODULE", None)
    if mod_api is None or getattr(mod_api, "_scidesktop_cache_sync", False):
        return

    orig_avail = mod_api.avail
    last_fp: list[tuple | None] = [None]

    async def _synced_avail(*args, **kwargs):
        if os.access(_CVMFS_SYNC_BIN, os.X_OK):
            try:
                proc = await asyncio.create_subprocess_exec(
                    _CVMFS_SYNC_BIN,
                    "--ensure",
                    stdout=asyncio.subprocess.DEVNULL,
                    stderr=asyncio.subprocess.DEVNULL,
                )
                try:
                    await asyncio.wait_for(proc.wait(), timeout=5.0)
                except asyncio.TimeoutError:
                    proc.kill()
                    await proc.wait()
            except OSError:
                pass

        fp = _modulepath_fingerprint()
        if last_fp[0] is not None and fp != last_fp[0]:
            mod_api.invalidate_module_caches()
        last_fp[0] = fp
        return await orig_avail(*args, **kwargs)

    mod_api.avail = _synced_avail
    mod_api._scidesktop_cache_sync = True


def _load_jupyter_server_extension(server_app):
    prev_hook = server_app.web_app.settings.get("page_config_hook")

    def _page_config_hook(handler, page_config):
        if prev_hook is not None:
            page_config = prev_hook(handler, page_config)
        disabled = page_config.get("disabledExtensions")
        if (
            not _ext_enabled_in(disabled, _REQUIRED_EXTENSION)
            or os.environ.get("SCIDESKTOP_KEEP_DISABLED_SERVER_PROXY") == "1"
            or _ext_enabled_in(page_config.get("lockedExtensions"), _REQUIRED_EXTENSION)
        ):
            return page_config
        user_dir = os.path.normpath(jupyter_paths.jupyter_config_dir())
        user_cfg = ConfigManager(
            read_config_path=[os.path.join(user_dir, "labconfig")]
        ).get("page_config")
        if (
            _ext_enabled_in(user_cfg.get("disabledExtensions"), _REQUIRED_EXTENSION)
            and _has_legacy_neurodesk_provenance(user_cfg)
            and not _disabled_without_legacy_user_entry(handler, user_dir)
        ):
            if isinstance(disabled, list):
                page_config["disabledExtensions"] = [
                    ext for ext in disabled if ext != _REQUIRED_EXTENSION
                ]
            elif isinstance(disabled, dict):
                disabled.pop(_REQUIRED_EXTENSION, None)
        return page_config

    server_app.web_app.settings["page_config_hook"] = _page_config_hook
    _install_lmod_cache_sync()
