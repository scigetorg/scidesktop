#!/bin/bash
# End-to-end check of an image that copies the sciget-molecular-imaging
# component: it configures only the molecular-imaging catalog and offers
# nothing outside it.
#
#   ./test/sciget-molecular-imaging-smoke.sh [image]
exec "$(dirname "$0")/sciget-catalog-check.sh" "${1:-moleculardesktop}" molecular-imaging stir qupath
