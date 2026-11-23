# Sourced by start.sh before the CVMFS hook (20-cvmfs): the repository that
# hook mounts in internal mode, unless the deployment names its own.
if [ -z "${SCIDESKTOP_CVMFS_REPOSITORIES:-}" ]; then
    export SCIDESKTOP_CVMFS_REPOSITORIES=neurodesk.ardc.edu.au
    _SCIDESKTOP_CVMFS_REPOS_DEFAULT=1
fi
