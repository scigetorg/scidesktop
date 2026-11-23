#!/bin/bash
# Component test for eessi-cvmfs: runs on the OS layer with its CVMFS client.
# Mounts nothing (a build has no FUSE); test/eessi-cvmfs-smoke.sh tests the live mount.
set -euo pipefail
repository=software.eessi.io

# CVMFS client resolves software.eessi.io to EESSI's mirrors and key.
config="$(cvmfs_config showconfig "${repository}")"
grep -q '^CVMFS_KEYS_DIR=/etc/cvmfs/keys/eessi\.io ' <<<"${config}"
grep -q '^CVMFS_USE_GEOAPI=yes ' <<<"${config}"
grep -qE '^CVMFS_SERVER_URL=.*eessi.*(/cvmfs/software\.eessi\.io|@fqrn@)' <<<"${config}"
grep -q 'BEGIN PUBLIC KEY' /etc/cvmfs/keys/eessi.io/eessi.io.pub

# Start hook sets software.eessi.io by default, appends to a component default
# (such as 18-neurodesk-cvmfs.sh), and respects an explicit operator override.
hook=/usr/local/bin/before-notebook.d/19-eessi-cvmfs.sh
[ "$(env -u SCIDESKTOP_CVMFS_REPOSITORIES bash -c ". ${hook}; echo \"\${SCIDESKTOP_CVMFS_REPOSITORIES}\"")" = "${repository}" ]
[ "$(SCIDESKTOP_CVMFS_REPOSITORIES=neurodesk.ardc.edu.au _SCIDESKTOP_CVMFS_REPOS_DEFAULT=1 bash -c ". ${hook}; echo \"\${SCIDESKTOP_CVMFS_REPOSITORIES}\"")" = "neurodesk.ardc.edu.au,${repository}" ]
[ "$(SCIDESKTOP_CVMFS_REPOSITORIES=other.example.org bash -c ". ${hook}; echo \"\${SCIDESKTOP_CVMFS_REPOSITORIES}\"")" = "other.example.org" ]
[ "$(printf '%s\n' "$(basename "${hook}")" 20-cvmfs | sort | head -n 1)" = "$(basename "${hook}")" ]
test -x /usr/local/bin/before-notebook.d/20-cvmfs

# Lmod modulepath provider is silent when EESSI is unmounted or disabled.
[ -z "$(/etc/scidesktop/modulepath.d/65-eessi)" ]
[ -z "$(SCIDESKTOP_CVMFS_MODE=disabled /etc/scidesktop/modulepath.d/65-eessi)" ]

# Dynamic app hook leaves SCIDESKTOP_APP_DIRS untouched when EESSI is unmounted.
app_hook=/usr/local/bin/before-notebook.d/32-eessi-apps.sh
[ -z "$(env -u SCIDESKTOP_APP_DIRS bash -c ". ${app_hook}; echo \"\${SCIDESKTOP_APP_DIRS:-}\"")" ]

# Helpers parse cleanly, validate arguments, and list configured launchers/modules.
bash -n "${hook}" "${app_hook}" /etc/scidesktop/modulepath.d/65-eessi /usr/local/bin/eessi-launch /usr/local/bin/eessi-catalog
! /usr/local/bin/eessi-launch >/dev/null 2>&1
! /usr/local/bin/eessi-launch ParaView paraview >/dev/null 2>&1
out="$(/usr/local/bin/eessi-catalog)"
grep -q 'ParaView (EESSI)' <<<"${out}"
grep -q 'GNU Octave (EESSI)' <<<"${out}"
grep -q 'GROMACS' <<<"${out}"

# Permissions and manifest.
[ "$(stat -c '%a %u' /etc/cvmfs/domain.d /etc/cvmfs/keys/eessi.io /etc/scidesktop/eessi-apps.d /etc/scidesktop/eessi-catalog.d)" = "$(printf '755 0\n755 0\n755 0\n755 0')" ]
test -r /opt/scidesktop/manifest.d/eessi-cvmfs.json
