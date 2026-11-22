# Sourced by start.sh after CVMFS is mounted (20-cvmfs) and sciget is set up
# (30-sciget): the components' module folders for the Jupyter server, which
# the Lmod panel and the kernels and terminals it starts inherit. The folders
# are the notebook user's, so they are listed as that user.
export LMOD_AVAIL_EXTENSIONS="${LMOD_AVAIL_EXTENSIONS:-no}"
if [ -x /opt/scidesktop/module-dirs ]; then
    if [ "$(id -u)" -eq 0 ]; then
        _modulepath_home="$(getent passwd "${NB_USER:-jovyan}" | cut -d: -f6)"
        _modulepath_dirs=$(runuser -u "${NB_USER:-jovyan}" -- env HOME="${_modulepath_home}" /opt/scidesktop/module-dirs)
    else
        _modulepath_dirs=$(/opt/scidesktop/module-dirs)
    fi
    # Keep component-provided directories in provider order (e.g. local modules
    # ahead of CVMFS) matching z01_lmod_modulepath.sh, while preserving any
    # non-provider directories ahead of them without shell glob expansion.
    _modulepath_base=""
    _modulepath_existing="${MODULEPATH:-}"
    while IFS= read -r -d ':' _modulepath_cur; do
        [ -n "${_modulepath_cur}" ] || continue
        case "
${_modulepath_dirs}
" in
            *"
${_modulepath_cur}
"*) continue ;;
        esac
        _modulepath_base="${_modulepath_base:+${_modulepath_base}:}${_modulepath_cur}"
    done <<<"${_modulepath_existing}:"
    while IFS= read -r _modulepath_dir; do
        [ -n "${_modulepath_dir}" ] || continue
        case ":${_modulepath_base}:" in
        *":${_modulepath_dir}:"*) ;;
        *) _modulepath_base="${_modulepath_base:+${_modulepath_base}:}${_modulepath_dir}" ;;
        esac
    done <<<"${_modulepath_dirs}"
    MODULEPATH="${_modulepath_base}"
    export MODULEPATH
    unset _modulepath_home _modulepath_dirs _modulepath_dir _modulepath_base _modulepath_existing _modulepath_cur
fi
