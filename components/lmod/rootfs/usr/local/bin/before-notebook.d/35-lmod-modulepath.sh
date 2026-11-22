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
    while IFS= read -r _modulepath_dir; do
        [ -n "${_modulepath_dir}" ] || continue
        case ":${MODULEPATH:-}:" in
        *":${_modulepath_dir}:"*) ;;
        *) MODULEPATH="${MODULEPATH:+${MODULEPATH}:}${_modulepath_dir}" ;;
        esac
    done <<<"${_modulepath_dirs}"
    export MODULEPATH
    unset _modulepath_home _modulepath_dirs _modulepath_dir
fi
