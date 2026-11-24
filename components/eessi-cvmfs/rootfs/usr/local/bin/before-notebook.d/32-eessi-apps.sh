# Sourced by start.sh after 20-cvmfs and before Jupyter starts:
# exposes EESSI desktop launchers (base + domain-specific entries in
# /etc/scidesktop/eessi-apps.d) to JupyterLab's Desktop applications launcher
# whenever /cvmfs/software.eessi.io is mounted and CVMFS is not disabled.
if [ "${SCIDESKTOP_CVMFS_MODE:-external}" != disabled ] \
    && [ -d /etc/scidesktop/eessi-apps.d ] \
    && ls /cvmfs/software.eessi.io/init/modules >/dev/null 2>&1; then
    _eessi_app_dirs="${SCIDESKTOP_APP_DIRS:-/opt/sciget/applications}"
    case ":${_eessi_app_dirs}:" in
    *:/etc/scidesktop/eessi-apps.d:*) ;;
    *) _eessi_app_dirs="${_eessi_app_dirs}:/etc/scidesktop/eessi-apps.d" ;;
    esac
    export SCIDESKTOP_APP_DIRS="${_eessi_app_dirs}"
    unset _eessi_app_dirs
fi
