#!/bin/bash
# End-to-end check of an image that copies the sciget-dermatology component:
# it configures only the dermatology catalog and offers nothing outside it.
#
#   ./test/sciget-dermatology-smoke.sh [image]
exec "$(dirname "$0")/sciget-catalog-check.sh" "${1:-dermdesktop}" dermatology qupath freesurfer
