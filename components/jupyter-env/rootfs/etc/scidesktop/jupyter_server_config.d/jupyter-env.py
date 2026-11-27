# Re-enable @jupyterhub/jupyter-server-proxy in memory when a shared home
# carries legacy neurodesktop's page_config.json disable (without mutating
# ~/.jupyter/labconfig/page_config.json on disk).
import os
import stat


def _has_legacy_neurodesk_provenance(page_config):
    if "neurodeskSupporter" in page_config:
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


def _scidesktop_page_config_hook(handler, page_config):
    disabled = page_config.get("disabledExtensions")
    if (
        isinstance(disabled, list)
        and "@jupyterhub/jupyter-server-proxy" in disabled
        and os.environ.get("SCIDESKTOP_KEEP_DISABLED_SERVER_PROXY") != "1"
        and _has_legacy_neurodesk_provenance(page_config)
    ):
        page_config["disabledExtensions"] = [
            ext for ext in disabled if ext != "@jupyterhub/jupyter-server-proxy"
        ]
    return page_config


c.ServerApp.tornado_settings.update({"page_config_hook": _scidesktop_page_config_hook})  # noqa: F821
