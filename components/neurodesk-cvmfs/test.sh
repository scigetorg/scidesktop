#!/bin/bash
# The component's own test: runs on the OS layer with its CVMFS client. It
# mounts nothing (a build has no FUSE); test/neurodesk-cvmfs-smoke.sh does.
set -euo pipefail
repository=neurodesk.ardc.edu.au

# The client resolves the repository to the component's mirrors and key.
config="$(cvmfs_config showconfig "${repository}")"
grep -q '^CVMFS_SERVER_URL=.*neurodesk\.org/cvmfs/neurodesk\.ardc\.edu\.au' <<<"${config}"
grep -q "^CVMFS_KEYS_DIR=/etc/cvmfs/keys/ardc.edu.au/ " <<<"${config}"
grep -q '^CVMFS_USE_GEOAPI=yes ' <<<"${config}"
grep -q 'BEGIN PUBLIC KEY' "/etc/cvmfs/keys/ardc.edu.au/${repository}.pub"

# The start hook names the repository for internal mode and keeps a
# deployment's own choice. It runs before the hook that mounts.
hook=/usr/local/bin/before-notebook.d/18-neurodesk-cvmfs.sh
[ "$(env -u SCIDESKTOP_CVMFS_REPOSITORIES bash -c ". ${hook}; echo \"\${SCIDESKTOP_CVMFS_REPOSITORIES}\"")" = "${repository}" ]
[ "$(SCIDESKTOP_CVMFS_REPOSITORIES=other.example.org bash -c ". ${hook}; echo \"\${SCIDESKTOP_CVMFS_REPOSITORIES}\"")" = other.example.org ]
[ "$(printf '%s\n' "$(basename "${hook}")" 20-cvmfs | sort | head -n 1)" = "$(basename "${hook}")" ]
test -x /usr/local/bin/before-notebook.d/20-cvmfs

# The folders the component adds to keep the OS layer's mode and owner.
[ "$(stat -c '%a %u' /etc/cvmfs/config.d /etc/cvmfs/keys/ardc.edu.au)" = "$(printf '755 0\n755 0')" ]
