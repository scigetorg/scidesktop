# Sourced by start.sh: tells OpenCode, in every terminal and in T3 Code, to
# read the Neurodesk model provider (/opt/neurodesk-agents/opencode.json) on
# top of the user's own configuration. OpenCode merges the two, and the
# user's ~/.config/opencode/opencode.json is not touched. A deployment's own
# OPENCODE_CONFIG is kept.
if [ -z "${OPENCODE_CONFIG:-}" ]; then
    export OPENCODE_CONFIG=/opt/neurodesk-agents/opencode.json
fi
