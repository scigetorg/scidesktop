#!/bin/bash
# Wrapper for the kernels `neurodesk kernel add` registers. It adds the module
# folders components name to MODULEPATH at the moment the kernel starts, not
# at the time the Jupyter server started: CVMFS may have been mounted, or a
# module installed, since then. A new terminal gets the same from
# /etc/profile.d.
# shellcheck source=/dev/null
source /etc/profile.d/z01_lmod_modulepath.sh >/dev/null 2>&1
exec "$@"
