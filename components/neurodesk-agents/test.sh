#!/bin/bash
# The component's own test: runs on the OS layer as the notebook user, with
# the coding agents and the home-defaults hook. Nothing here talks to a
# model provider.
set -euo pipefail
export HOME="$(mktemp -d)"
trap 'rm -rf "${HOME}"' EXIT
cd "${HOME}"
component=/opt/neurodesk-agents

# A new home gets the instructions where each agent reads its user-level ones,
# beside the settings coding-agents ships, which stay as they are.
/usr/local/bin/before-notebook.d/25-home-defaults
for file in .codex/AGENTS.md .claude/CLAUDE.md .config/opencode/AGENTS.md; do
    cmp "${HOME}/${file}" "${component}/AGENTS.md"
done
for file in .codex/config.toml .claude/settings.json .config/opencode/opencode.json; do
    cmp "${HOME}/${file}" "/etc/scidesktop/home-defaults/${file}"
done
# A file the user already has is theirs.
echo mine > "${HOME}/.codex/AGENTS.md.new" && mv "${HOME}/.codex/AGENTS.md.new" "${HOME}/.codex/AGENTS.md"
/usr/local/bin/before-notebook.d/25-home-defaults
[ "$(cat "${HOME}/.codex/AGENTS.md")" = mine ]

# The start hook points OpenCode at the provider file and keeps a
# deployment's own choice.
hook=/usr/local/bin/before-notebook.d/45-neurodesk-agents.sh
[ "$(env -u OPENCODE_CONFIG bash -c ". ${hook}; echo \"\${OPENCODE_CONFIG}\"")" = "${component}/opencode.json" ]
[ "$(OPENCODE_CONFIG=/elsewhere.json bash -c ". ${hook}; echo \"\${OPENCODE_CONFIG}\"")" = /elsewhere.json ]

# OpenCode offers the Neurodesk model with the hook's setting, on top of the
# user's own configuration, and does not without it. No key is needed to list.
. "${hook}"
# OpenCode gives its own start-up a fixed time ("Location plugins did not
# finish activating"), which a builder running every component's test at once
# can exceed. Only that error is tried again.
for attempt in 1 2 3 4 5; do
    opencode models --standalone > "${HOME}/models" 2>&1 && break
    if [ "${attempt}" = 5 ] || ! grep -q 'did not finish activating' "${HOME}/models"; then
        cat "${HOME}/models" >&2
        exit 1
    fi
done
grep -qx 'neurodesk/neurodesk' "${HOME}/models" || { cat "${HOME}/models" >&2; exit 1; }
env -u OPENCODE_CONFIG opencode models --standalone > "${HOME}/models-without" 2>&1
if grep -q '^neurodesk/' "${HOME}/models-without"; then
    echo "OpenCode offers the Neurodesk model without the hook's setting" >&2
    exit 1
fi

# The key comes from the session's environment and nowhere else: no secret,
# token or default model is preset.
grep -q '"apiKey": "{env:NEURODESK_API_KEY}"' "${component}/opencode.json"
[ -z "${NEURODESK_API_KEY:-}" ]
if grep -rnE '"model"|sk-[A-Za-z0-9]{8}|Bearer ' "${component}"; then
    echo "the files above preset a model or carry a credential" >&2
    exit 1
fi
