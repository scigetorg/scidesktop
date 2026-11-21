#!/bin/bash
# End-to-end check of an image that copies the neurodesk-agents component.
#
#   ./test/neurodesk-agents-smoke.sh [image]
#
# Runs what a terminal runs: a login shell of the notebook user, after the
# image's start hooks. OpenCode lists its models, which asks no model
# anything and needs no key.

set -uo pipefail

IMAGE="${1:-neurodesktop}"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

echo "neurodesk-agents smoke: ${IMAGE}"
out=$(docker run --rm "${IMAGE}" bash -lc '
    echo "config=${OPENCODE_CONFIG:-}"
    echo "key=${NEURODESK_API_KEY:-unset}"
    for file in .codex/AGENTS.md .claude/CLAUDE.md .config/opencode/AGENTS.md; do
        cmp -s "${HOME}/${file}" /opt/neurodesk-agents/AGENTS.md && echo "instructions=${file}"
    done
    for file in .codex/config.toml .claude/settings.json .config/opencode/opencode.json; do
        cmp -s "${HOME}/${file}" "/etc/scidesktop/home-defaults/${file}" && echo "settings=${file}"
    done
    cd /tmp && opencode models --standalone 2>&1 | grep "^neurodesk/"' 2>/dev/null)

has() { printf '%s\n' "${out}" | grep -qxF "$1"; }

has "config=/opt/neurodesk-agents/opencode.json" \
    && pass "the session points OpenCode at the Neurodesk provider" \
    || fail "the session points OpenCode at the Neurodesk provider"
has "neurodesk/neurodesk" && pass "OpenCode offers the Neurodesk model" || fail "OpenCode offers the Neurodesk model"
has "key=unset" && pass "no Neurodesk key is preset" || fail "no Neurodesk key is preset"
for file in .codex/AGENTS.md .claude/CLAUDE.md .config/opencode/AGENTS.md; do
    has "instructions=${file}" && pass "a new home gets ~/${file}" || fail "a new home gets ~/${file}"
done
for file in .codex/config.toml .claude/settings.json .config/opencode/opencode.json; do
    has "settings=${file}" && pass "the agents' own ~/${file} is unchanged" || fail "the agents' own ~/${file} is unchanged"
done

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "neurodesk-agents smoke: all checks passed"
else
    echo "neurodesk-agents smoke: ${FAILED} check(s) failed; the session printed:"
    printf '%s\n' "${out}" | sed 's/^/        /'
fi
exit "${FAILED}"
