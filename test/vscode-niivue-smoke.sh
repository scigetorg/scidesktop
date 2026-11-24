#!/bin/bash
exec "$(dirname "$0")/vscode-extensions-smoke.sh" vscode-niivue "${1:-neurodesktop}"
