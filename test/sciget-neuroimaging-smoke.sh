#!/bin/bash
# End-to-end check of an image that copies the sciget-neuroimaging component:
# it offers the neuroimaging tools and no microscopy tool.
#
#   ./test/sciget-neuroimaging-smoke.sh [image]
exec "$(dirname "$0")/sciget-catalog-check.sh" "${1:-neurodesktop}" neuroimaging niimath nextpyp
