#!/bin/bash
# End-to-end check of an image that copies the jupyterlab-neuroglancer component.
#
#   ./test/jupyterlab-neuroglancer-smoke.sh [image]
exec "$(dirname "$0")/viewer-smoke.sh" "${1:-microdesktop}" jupyterlab-neuroglancer
