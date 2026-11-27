#!/bin/bash
# Wrapper for the kernels `scigethelpers kernel add` and `scigethelpers uv`
# register. It adds the module folders components name to MODULEPATH at the
# moment the kernel starts, not at the time the Jupyter server started: CVMFS
# may have been mounted, or a module installed, since then. A new terminal gets
# the same from /etc/profile.d.
# shellcheck source=/dev/null
source /etc/profile.d/z01_lmod_modulepath.sh >/dev/null 2>&1
if [ "${2:-}" = "-I" ] && [ "${4:-}" = "launch" ]; then
    export _SCIGETHELPERS_MODULEPATH_REFRESHED=1
fi
exec "$@"
