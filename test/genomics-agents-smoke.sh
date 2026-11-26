#!/bin/bash
# End-to-end check of an image that copies the genomics-agents component.
#
#   ./test/genomics-agents-smoke.sh [image]
#
# Verifies that a fresh session populates user-level agent instructions for
# Codex, Claude Code and OpenCode without disturbing coding-agents settings or
# presetting any model or credential.

set -uo pipefail

IMAGE="${1:-genomicsdesktop}"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

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

has() { printf '%s\n' "${out}" | grep -qxF "$1"; }

for file in .codex/AGENTS.md .claude/CLAUDE.md .config/opencode/AGENTS.md; do
    has "instructions=${file}" && pass "a new home gets ~/${file}" || fail "a new home gets ~/${file}"
done
for file in .codex/config.toml .claude/settings.json .config/opencode/opencode.json; do
    has "settings=${file}" && pass "the agents' own ~/${file} is unchanged" || fail "the agents' own ~/${file} is unchanged"
done
has "mentions_viash_catalog=ok" && pass "instructions document viash-catalog" || fail "instructions document viash-catalog"
has "mentions_nf_config=ok" && pass "instructions document scidesktop Nextflow Apptainer config" || fail "instructions document scidesktop Nextflow Apptainer config"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "genomics-agents smoke: all checks passed"
else
    echo "genomics-agents smoke: ${FAILED} check(s) failed; output:"
    printf '%s\n' "${out}" | sed 's/^/        /'
fi
exit "${FAILED}"
