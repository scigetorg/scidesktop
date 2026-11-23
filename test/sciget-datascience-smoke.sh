#!/bin/bash
# End-to-end check of an image that copies the sciget-datascience component:
# it configures only the datascience catalog and offers nothing outside it.
#
#   ./test/sciget-datascience-smoke.sh [image]
exec "$(dirname "$0")/sciget-catalog-check.sh" "${1:-aidesktop}" datascience postgresanalytics
