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
    for _scidesktop_dir in ${_scidesktop_dirs}; do
        case ":${MODULEPATH:-}:" in
        *":${_scidesktop_dir}:"*) ;;
        *) MODULEPATH="${MODULEPATH:+${MODULEPATH}:}${_scidesktop_dir}" ;;
        esac
    done
    IFS=$_scidesktop_ifs
    export MODULEPATH
    unset _scidesktop_dirs _scidesktop_ifs _scidesktop_dir
fi
