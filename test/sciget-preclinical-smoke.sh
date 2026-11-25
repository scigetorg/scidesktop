#!/bin/bash
# End-to-end check of an image that copies the sciget-preclinical component:
# it configures only the preclinical catalog and offers nothing outside it.
#
#   ./test/sciget-preclinical-smoke.sh [image]
exec "$(dirname "$0")/sciget-catalog-check.sh" "${1:-preclinicaldesktop}" preclinical brkraw qupath
