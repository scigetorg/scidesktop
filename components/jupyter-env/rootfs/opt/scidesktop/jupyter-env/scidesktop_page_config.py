"""SciDesktop Jupyter Server runtime hooks.

1. Keep `@jupyterhub/jupyter-server-proxy` enabled in rendered Lab `page_config`
   even when a legacy Neurodesktop session on a shared home wrote
   `"@jupyterhub/jupyter-server-proxy": true` into
   `~/.jupyter/labconfig/page_config.json`. Chains after JupyterHub's own
   `page_config_hook` (Jupyter Server loads extensions in alphabetical order, so
   `scidesktop_page_config` loads after `jupyterhub`) without mutating the
   shared file or affecting concurrent legacy Neurodesktop sessions.

2. Keep `jupyterlmod`'s in-memory `avail_cache` synchronized with on-disk
   `MODULEPATH` updates (such as background `sciget refresh` /
   `cvmfs-domain-modules` sync or `sciget install` after the server starts).
"""

import asyncio
import os

_REQUIRED_EXTENSION = "@jupyterhub/jupyter-server-proxy"
_CVMFS_SYNC_BIN = "/opt/scidesktop/cvmfs-domain-modules"


def _jupyter_server_extension_points():
    return [{"module": "scidesktop_page_config"}]


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
        if isinstance(disabled, list):
            page_config["disabledExtensions"] = [
                ext for ext in disabled if ext != _REQUIRED_EXTENSION
            ]
        elif isinstance(disabled, dict):
            disabled.pop(_REQUIRED_EXTENSION, None)
        return page_config

    server_app.web_app.settings["page_config_hook"] = _page_config_hook
    _install_lmod_cache_sync()
