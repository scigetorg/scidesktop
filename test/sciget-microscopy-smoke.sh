#!/bin/bash
# End-to-end check of an image that copies the sciget-microscopy component:
# it configures only the microscopy catalog and offers nothing outside it.
#
#   ./test/sciget-microscopy-smoke.sh [image]
exec "$(dirname "$0")/sciget-catalog-check.sh" "${1:-microdesktop}" microscopy nextpyp
