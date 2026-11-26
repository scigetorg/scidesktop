#!/bin/bash
# End-to-end check of an image that copies the sciget-genomics component:
# it configures only the genomics catalog and offers nothing outside it.
#
#   ./test/sciget-genomics-smoke.sh [image]
exec "$(dirname "$0")/sciget-catalog-check.sh" "${1:-genomicsdesktop}" genomics nextflow niimath
