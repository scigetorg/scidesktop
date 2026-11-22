# Sourced by start.sh so Jupyter kernels, terminals, and desktop inherit
# Neurodesk's FreeSurfer, nf-neuro, and legacy /neurodesktop-storage defaults.
_nd_home="${HOME:-}"
if [ "$(id -u)" -eq 0 ]; then
    _nd_pw_home="$(getent passwd "${NB_USER:-jovyan}" 2>/dev/null | cut -d: -f6 || true)"
    [ -n "${_nd_pw_home}" ] && _nd_home="${_nd_pw_home}"
    unset _nd_pw_home
fi
if [ -z "${APPTAINERENV_SUBJECTS_DIR:-}" ] && [ -n "${_nd_home}" ]; then
    export APPTAINERENV_SUBJECTS_DIR="${_nd_home}/freesurfer-subjects-dir"
fi
export NF_NEURO_MODULES_DIR="${NF_NEURO_MODULES_DIR:-/opt/nf-neuro/modules}"
unset _nd_home

# Append /neurodesktop-storage to APPTAINER_BINDPATH only when mounted/present,
# traversable by the session user, and bind overrides/empty opt-out were not set.
if [ -d /neurodesktop-storage ] \
    && [ -z "${APPTAINER_BIND+x}" ] && [ -z "${SINGULARITY_BIND+x}" ] && [ -z "${SINGULARITY_BINDPATH+x}" ]; then
    _nd_opt_out=0
    if [ "${APPTAINER_BINDPATH+x}" = x ] && [ -z "${APPTAINER_BINDPATH}" ]; then
        _nd_opt_out=1
    fi
    if [ "${_nd_opt_out}" -eq 0 ]; then
        _nd_ok=0
        if [ "$(id -u)" -eq 0 ] && [ -x /opt/scidesktop/run-as-user ]; then
            /opt/scidesktop/run-as-user test -r /neurodesktop-storage -a -x /neurodesktop-storage 2>/dev/null && _nd_ok=1
        else
            test -r /neurodesktop-storage -a -x /neurodesktop-storage 2>/dev/null && _nd_ok=1
        fi
        if [ "${_nd_ok}" -eq 1 ]; then
            case ",${APPTAINER_BINDPATH:-}," in
                *,/neurodesktop-storage,*) ;;
                *) export APPTAINER_BINDPATH="${APPTAINER_BINDPATH:+${APPTAINER_BINDPATH},}/neurodesktop-storage" ;;
            esac
        fi
        unset _nd_ok
    fi
    unset _nd_opt_out
fi
