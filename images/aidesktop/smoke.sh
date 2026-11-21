#!/bin/bash
# This image's own end-to-end checks, beside the base's (test/smoke.sh). CI
# runs an image's smoke.sh when it has one (docs/images.md).
#
#   images/aidesktop/smoke.sh [image]
exec "$(dirname "$0")/../../test/ai-ready-smoke.sh" "${1:-aidesktop}"
