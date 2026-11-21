#!/bin/bash
# End-to-end check of an image that copies the sciget-microscopy component:
# it offers the microscopy tools and no neuroimaging tool.
#
#   ./test/sciget-microscopy-smoke.sh [image]
exec "$(dirname "$0")/sciget-catalog-check.sh" "${1:-microdesktop}" microscopy nextpyp niimath
