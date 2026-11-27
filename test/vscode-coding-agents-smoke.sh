#!/bin/bash
exec "$(dirname "$0")/vscode-extensions-smoke.sh" vscode-coding-agents "${1:-scidesktop}"
