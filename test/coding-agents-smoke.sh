#!/bin/bash
# End-to-end check of an image that copies the coding-agents component.
#
#   ./test/coding-agents-smoke.sh [image]
#
# Runs what a terminal runs: a login shell of the notebook user, after the
# image's start hooks. Nothing here talks to a model provider.

set -uo pipefail

IMAGE="${1:-microdesktop}"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

echo "coding-agents smoke: ${IMAGE}"
out=$(docker run --rm "${IMAGE}" bash -lc '
    echo "user=$(id -un)"
    for agent in codex claude opencode; do
        echo "${agent}=$("${agent}" --version 2>/dev/null | head -n 1) at $(readlink -f "$(command -v "${agent}")")"
    done
    for file in .codex/config.toml .claude/settings.json .config/opencode/opencode.json; do
        [ -s "${HOME}/${file}" ] && echo "default=${file}"
    done
    cat /opt/scidesktop/manifest.d/coding-agents.json' 2>/dev/null)

version() { printf '%s\n' "${out}" | sed -n "s/.*\"$1\": \"\([^\"]*\)\".*/\1/p"; }
has() { printf '%s\n' "${out}" | grep -qxF "$1"; }

has "user=jovyan" && pass "the session runs as the notebook user" || fail "the session runs as the notebook user"
has "codex=codex-cli $(version codex) at /opt/coding-agents/bin/codex" \
    && pass "codex $(version codex) runs" || fail "codex runs"
has "claude=$(version claude-code) (Claude Code) at /opt/coding-agents/bin/claude" \
    && pass "claude $(version claude-code) runs" || fail "claude runs"
has "opencode=opencode v$(version opencode) at /opt/coding-agents/bin/opencode" \
    && pass "opencode $(version opencode) runs" || fail "opencode runs"
for file in .codex/config.toml .claude/settings.json .config/opencode/opencode.json; do
    has "default=${file}" && pass "a new home gets ~/${file}" || fail "a new home gets ~/${file}"
done

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "coding-agents smoke: all checks passed"
else
    echo "coding-agents smoke: ${FAILED} check(s) failed; the session printed:"
    printf '%s\n' "${out}" | sed 's/^/        /'
fi
exit "${FAILED}"
