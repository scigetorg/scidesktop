# Sourced by start.sh after 18-neurodesk-cvmfs.sh and before 20-cvmfs:
# ensures software.eessi.io is included in SCIDESKTOP_CVMFS_REPOSITORIES for
# internal mode without overwriting an explicit operator override.
if [ -z "${SCIDESKTOP_CVMFS_REPOSITORIES:-}" ]; then
    export SCIDESKTOP_CVMFS_REPOSITORIES=software.eessi.io
elif [ "${_SCIDESKTOP_CVMFS_REPOS_DEFAULT:-0}" = 1 ]; then
    case ",${SCIDESKTOP_CVMFS_REPOSITORIES}," in
    *,software.eessi.io,*) ;;
    *) export SCIDESKTOP_CVMFS_REPOSITORIES="${SCIDESKTOP_CVMFS_REPOSITORIES},software.eessi.io" ;;
    esac
fi
unset _SCIDESKTOP_CVMFS_REPOS_DEFAULT
