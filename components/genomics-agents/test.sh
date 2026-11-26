#!/bin/bash
# The component's own test: runs on the OS layer as the notebook user, with
# coding-agents and the home-defaults hook. Nothing talks to a model provider.
set -euo pipefail
HOME="$(mktemp -d)"
export HOME
trap 'rm -rf "${HOME}"' EXIT
cd "${HOME}"
component=/opt/genomics-agents

# A new home gets the instructions where each agent reads its user-level ones,
# beside the settings coding-agents ships, which stay intact.
/usr/local/bin/before-notebook.d/25-home-defaults
for file in .codex/AGENTS.md .claude/CLAUDE.md .config/opencode/AGENTS.md; do
    cmp "${HOME}/${file}" "${component}/AGENTS.md"
done
for file in .codex/config.toml .claude/settings.json .config/opencode/opencode.json; do
    cmp "${HOME}/${file}" "/etc/scidesktop/home-defaults/${file}"
done

# A file the user already has is preserved on subsequent startups.
echo mine > "${HOME}/.codex/AGENTS.md.new" && mv "${HOME}/.codex/AGENTS.md.new" "${HOME}/.codex/AGENTS.md"
/usr/local/bin/before-notebook.d/25-home-defaults
[ "$(cat "${HOME}/.codex/AGENTS.md")" = mine ]

# Switching domain images with a persistent home refreshes dangling image-managed
# /opt/*-agents/* symlinks while preserving custom user symlinks.
ln -sf /opt/neurodesk-agents/AGENTS.md "${HOME}/.claude/CLAUDE.md"
ln -sf /tmp/user-custom-agents-missing.md "${HOME}/.config/opencode/AGENTS.md"
/usr/local/bin/before-notebook.d/25-home-defaults
[ "$(readlink "${HOME}/.claude/CLAUDE.md")" = "${component}/AGENTS.md" ]
[ "$(readlink "${HOME}/.config/opencode/AGENTS.md")" = "/tmp/user-custom-agents-missing.md" ]

# No secret, token or preset model is shipped.
if grep -rnE '"model"|sk-[A-Za-z0-9]{8}|Bearer ' "${component}"; then
    echo "genomics-agents unexpectedly presets a model or carries a credential" >&2
    exit 1
fi
