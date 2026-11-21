#!/bin/bash
exec "$(dirname "$0")/vscode-extensions-smoke.sh" vscode-core "${1:-microdesktop}"
