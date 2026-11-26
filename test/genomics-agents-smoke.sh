#!/bin/bash
# End-to-end check of an image that copies the genomics-agents component.
#
#   ./test/genomics-agents-smoke.sh [image]
#
# Verifies that:
#   - A fresh session populates user-level agent instructions for Codex, Claude
#     Code and OpenCode without disturbing coding-agents settings
#   - Switching from another domain image (dangling /opt/neurodesk-agents/AGENTS.md)
#     with a persistent mounted home (including a foreign UID) refreshes the
#     image-managed link while preserving user files and custom symlinks

set -uo pipefail

IMAGE="${1:-genomicsdesktop}"
FAILED=0
SWITCH_HOME=""

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() {
    [ -z "${SWITCH_HOME}" ] || rm -rf "${SWITCH_HOME}"
}
trap cleanup EXIT

echo "genomics-agents smoke: ${IMAGE}"
out=$(docker run --rm --network none -e SCIDESKTOP_SLURM=no "${IMAGE}" bash -lc '
    for file in .codex/AGENTS.md .claude/CLAUDE.md .config/opencode/AGENTS.md; do
        cmp -s "${HOME}/${file}" /opt/genomics-agents/AGENTS.md && echo "instructions=${file}"
    done
    for file in .codex/config.toml .claude/settings.json .config/opencode/opencode.json; do
        cmp -s "${HOME}/${file}" "/etc/scidesktop/home-defaults/${file}" && echo "settings=${file}"
    done
    grep -q "viash-catalog" /opt/genomics-agents/AGENTS.md && echo "mentions_viash_catalog=ok"
    grep -q "/etc/scidesktop/nextflow/scidesktop.config" /opt/genomics-agents/AGENTS.md && echo "mentions_nf_config=ok"
' 2>/dev/null)

# Simulate switching from neurodesktop to genomicsdesktop on a persistent home
# with a foreign UID (12345:100): dangling /opt/neurodesk-agents/AGENTS.md is
# refreshed, while user-owned files and custom symlinks are preserved.
SWITCH_HOME="$(mktemp -d)"
chmod 0777 "${SWITCH_HOME}"
mkdir -p "${SWITCH_HOME}/.codex" "${SWITCH_HOME}/.claude" "${SWITCH_HOME}/.config/opencode"
chmod 0777 "${SWITCH_HOME}/.codex" "${SWITCH_HOME}/.claude" "${SWITCH_HOME}/.config" "${SWITCH_HOME}/.config/opencode"
ln -s /opt/neurodesk-agents/AGENTS.md "${SWITCH_HOME}/.codex/AGENTS.md"
echo "custom-user-claude" > "${SWITCH_HOME}/.claude/CLAUDE.md"
chmod 0644 "${SWITCH_HOME}/.claude/CLAUDE.md"
ln -s /tmp/custom-nonexistent-agents.md "${SWITCH_HOME}/.config/opencode/AGENTS.md"

switch_out=$(docker run --rm --network none --user 12345:100 \
    -e HOME=/home/jovyan -e SCIDESKTOP_SLURM=no \
    -v "${SWITCH_HOME}:/home/jovyan" "${IMAGE}" bash -lc '
    [ "$(readlink "${HOME}/.codex/AGENTS.md")" = "/opt/genomics-agents/AGENTS.md" ] && echo "switch_refreshed=ok"
    [ "$(cat "${HOME}/.claude/CLAUDE.md")" = "custom-user-claude" ] && echo "switch_kept_file=ok"
    [ "$(readlink "${HOME}/.config/opencode/AGENTS.md")" = "/tmp/custom-nonexistent-agents.md" ] && echo "switch_kept_custom_link=ok"
    rm -rf "${HOME}/.local" "${HOME}/.cache" "${HOME}/.codex" "${HOME}/.claude" "${HOME}/.config" 2>/dev/null || true
' 2>/dev/null)

has() { printf '%s\n%s\n' "${out}" "${switch_out}" | grep -qxF "$1"; }

for file in .codex/AGENTS.md .claude/CLAUDE.md .config/opencode/AGENTS.md; do
    has "instructions=${file}" && pass "a new home gets ~/${file}" || fail "a new home gets ~/${file}"
done
for file in .codex/config.toml .claude/settings.json .config/opencode/opencode.json; do
    has "settings=${file}" && pass "the agents' own ~/${file} is unchanged" || fail "the agents' own ~/${file} is unchanged"
done
has "mentions_viash_catalog=ok" && pass "instructions document viash-catalog" || fail "instructions document viash-catalog"
has "mentions_nf_config=ok" && pass "instructions document scidesktop Nextflow Apptainer config" || fail "instructions document scidesktop Nextflow Apptainer config"
has "switch_refreshed=ok" && pass "domain switch (foreign UID) refreshes dangling /opt/*-agents/* symlink" || fail "domain switch (foreign UID) refreshes dangling /opt/*-agents/* symlink"
has "switch_kept_file=ok" && pass "domain switch preserves user-owned instruction file" || fail "domain switch preserves user-owned instruction file"
has "switch_kept_custom_link=ok" && pass "domain switch preserves user's custom symlink" || fail "domain switch preserves user's custom symlink"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "genomics-agents smoke: all checks passed"
else
    echo "genomics-agents smoke: ${FAILED} check(s) failed; output:"
    printf '%s\n%s\n' "${out}" "${switch_out}" | sed 's/^/        /'
fi
exit "${FAILED}"
