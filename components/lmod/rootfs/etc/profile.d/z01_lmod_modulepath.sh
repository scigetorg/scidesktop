# Adds the module folders components name (/opt/scidesktop/module-dirs) after
# Lmod's own, so a new shell sees modules installed or mounted since the last.
# Also sourced for interactive shells that are not login shells
# (/etc/bash.bashrc.d/lmod.sh).
# Keep `module avail` focused on loadable modules; users can opt back in with
# LMOD_AVAIL_EXTENSIONS=yes.
export LMOD_AVAIL_EXTENSIONS="${LMOD_AVAIL_EXTENSIONS:-no}"
if [ -x /opt/scidesktop/module-dirs ]; then
    _scidesktop_dirs=$(/opt/scidesktop/module-dirs)
    _scidesktop_ifs=$IFS
    IFS='
'
    # Keep component-provided directories in provider order (e.g. local modules
    # ahead of CVMFS) even if a parent shell inherited CVMFS first, while
    # preserving any user `module use` directories ahead of them.
    _scidesktop_base=""
    _scidesktop_existing="${MODULEPATH:-}"
    IFS=':'
    for _scidesktop_cur in ${_scidesktop_existing}; do
        [ -n "${_scidesktop_cur}" ] || continue
        case "
${_scidesktop_dirs}
" in
            *"
${_scidesktop_cur}
"*) continue ;;
        esac
        _scidesktop_base="${_scidesktop_base:+${_scidesktop_base}:}${_scidesktop_cur}"
    done
    IFS='
'
    for _scidesktop_dir in ${_scidesktop_dirs}; do
        [ -n "${_scidesktop_dir}" ] || continue
        case ":${_scidesktop_base}:" in
        *":${_scidesktop_dir}:"*) ;;
        *) _scidesktop_base="${_scidesktop_base:+${_scidesktop_base}:}${_scidesktop_dir}" ;;
        esac
    done
    IFS=$_scidesktop_ifs
    MODULEPATH="${_scidesktop_base}"
    export MODULEPATH
    unset _scidesktop_dirs _scidesktop_ifs _scidesktop_dir _scidesktop_base _scidesktop_existing _scidesktop_cur
fi
