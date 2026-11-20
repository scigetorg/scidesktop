# Sourced by start.sh: Apptainer settings for the Jupyter server, which the
# kernels, terminals and desktop it starts inherit. Explicit values are kept.
#
# APPTAINER_HOME: the notebook user's home. Without it Apptainer looks the
# home up in the password database for the host uid in /proc/self/uid_map;
# under rootless Podman that uid has no entry here, and every container fails
# with "failed to add  as session directory: path . is not an absolute path".
#
# APPTAINER_NV: 1 when the NVIDIA driver is loaded, so Apptainer binds its
# devices and libraries. An X server on that driver selects NVIDIA's GLX
# library, which tool containers do not ship. Set APPTAINER_NV=0 when a host
# library needs a newer glibc than a tool container has.
if [ -z "${APPTAINER_HOME:-}" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        _apptainer_home="$(getent passwd "${NB_USER:-jovyan}" | cut -d: -f6)"
    else
        _apptainer_home="${HOME:-}"
    fi
    if [ -n "${_apptainer_home}" ] && [ -d "${_apptainer_home}" ]; then
        export APPTAINER_HOME="${_apptainer_home}"
    fi
    unset _apptainer_home
fi
if [ -z "${APPTAINER_NV+x}" ] && [ -f /proc/driver/nvidia/version ]; then
    export APPTAINER_NV=1
fi
