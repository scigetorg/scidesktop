#!/bin/bash
# End-to-end check of an image that copies the jupyterlab-niivue component.
#
#   ./test/jupyterlab-niivue-smoke.sh [image]
exec "$(dirname "$0")/viewer-smoke.sh" "${1:-neurodesktop}" jupyterlab-niivue
