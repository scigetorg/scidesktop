# shellcheck shell=bash
# Sourced by start.sh: export Nextflow Apptainer cache directories and the
# shared scidesktop Nextflow config path to the Jupyter server and its kernels.
if [ -z "${SCIDESKTOP_NEXTFLOW_CONFIG:-}" ]; then
    export SCIDESKTOP_NEXTFLOW_CONFIG=/etc/scidesktop/nextflow/scidesktop.config
fi
if [ "$(/usr/bin/id -u)" -eq 0 ]; then
    _wf_home="$(/usr/bin/getent passwd "${NB_USER:-jovyan}" | cut -d: -f6)"
else
    _wf_home="${HOME:-}"
fi
if [ -n "${_wf_home}" ] && [ "${_wf_home}" != "/root" ]; then
    _wf_cache="${XDG_CACHE_HOME:-${_wf_home}/.cache}/nextflow"
    if [ -z "${NXF_APPTAINER_CACHEDIR:-}" ]; then
        export NXF_APPTAINER_CACHEDIR="${_wf_cache}/apptainer"
    fi
    if [ -z "${NXF_SINGULARITY_CACHEDIR:-}" ]; then
        export NXF_SINGULARITY_CACHEDIR="${_wf_cache}/singularity"
    fi
    unset _wf_cache
fi
unset _wf_home
