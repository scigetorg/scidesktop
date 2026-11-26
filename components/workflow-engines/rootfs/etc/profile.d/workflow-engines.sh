# Defaults for Nextflow container caching and shared scidesktop profiles.
# Login shells read this file; interactive shells read /etc/bash.bashrc.d and
# Jupyter sessions get the same defaults from before-notebook.d.
if [ -z "${SCIDESKTOP_NEXTFLOW_CONFIG:-}" ]; then
    export SCIDESKTOP_NEXTFLOW_CONFIG=/etc/scidesktop/nextflow/scidesktop.config
fi
if [ -n "${HOME:-}" ] && [ "${HOME}" != "/root" ]; then
    _wf_cache="${XDG_CACHE_HOME:-${HOME}/.cache}/nextflow"
    if [ -z "${NXF_APPTAINER_CACHEDIR:-}" ]; then
        export NXF_APPTAINER_CACHEDIR="${_wf_cache}/apptainer"
    fi
    if [ -z "${NXF_SINGULARITY_CACHEDIR:-}" ]; then
        export NXF_SINGULARITY_CACHEDIR="${_wf_cache}/singularity"
    fi
    unset _wf_cache
fi
