#!/bin/bash
# The component's own test: runs on the OS layer as the notebook user, with
# nothing from the base image but the OS.
set -euo pipefail
HOME="$(mktemp -d)"
export HOME
trap 'rm -rf "${HOME}"' EXIT
cd "${HOME}"

# Each agent is the command a terminal finds, and it starts on this OS.
for agent in codex claude opencode; do
    [ "$(readlink -f "$(command -v "${agent}")")" = "/opt/coding-agents/bin/${agent}" ]
    "${agent}" --version
done

# The manifest names the versions that answer.
manifest=/opt/scidesktop/manifest.d/coding-agents.json
version() { sed -n "s/.*\"$1\": \"\([^\"]*\)\".*/\1/p" "${manifest}"; }
[ "$(codex --version)" = "codex-cli $(version codex)" ]
[ "$(claude --version)" = "$(version claude-code) (Claude Code)" ]
[ "$(opencode --version)" = "opencode v$(version opencode)" ]

# The defaults a new home gets only turn off self-updates: the binaries
# belong to the image. No provider, model, key or endpoint is preset.
defaults=/etc/scidesktop/home-defaults
grep -qx 'check_for_update_on_startup = false' "${defaults}/.codex/config.toml"
grep -q '"DISABLE_AUTOUPDATER": "1"' "${defaults}/.claude/settings.json"
grep -q '"autoupdate": false' "${defaults}/.config/opencode/opencode.json"
if grep -rilE 'api[_-]?key|base_?url|"model"|token' "${defaults}/.codex" "${defaults}/.claude" "${defaults}/.config/opencode"; then
    echo "the home defaults above preset a provider or a credential" >&2
    exit 1
fi

# T3 Code provider defaults point at the bundled binaries and keep Codex in
# existing-CLI mode without presetting any credential or model.
t3_defaults=/etc/scidesktop/t3-code/settings.d/20-coding-agents.json
grep -q '"/opt/coding-agents/bin/codex"' "${t3_defaults}"
grep -q '"setupMode": "existing"' "${t3_defaults}"
grep -q '"/opt/coding-agents/bin/opencode"' "${t3_defaults}"
if grep -iE 'api[_-]?key|base_?url|"model"|token' "${t3_defaults}"; then
    echo "T3 Code defaults above preset a credential or model" >&2
    exit 1
fi

# Every binary comes with its licence or notice.
for notice in codex-LICENSE codex-NOTICE claude-code-LICENSE.md opencode-LICENSE; do
    test -s "/opt/coding-agents/licenses/${notice}"
done

# Nothing root-owned is writable by group or others, and the user can read it all.
if find /opt/coding-agents "${defaults}/.codex" "${defaults}/.claude" "${defaults}/.config/opencode" \
        "${t3_defaults}" \
        ! -type l \( -perm /022 -o ! -readable \) -print | grep .; then
    echo "bad permissions on the files above" >&2
    exit 1
fi
