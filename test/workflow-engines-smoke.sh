#!/bin/bash
# End-to-end check of an image that copies the workflow-engines component.
#
#   ./test/workflow-engines-smoke.sh [image]
#
# Verifies Nextflow (offline fat jar), nf-test, and Snakemake execute cleanly
# in a login shell without altering the session's default Python.

set -uo pipefail

IMAGE="${1:-scidesktop}"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

echo "workflow-engines smoke: ${IMAGE}"
out=$(docker run --rm "${IMAGE}" bash -lc '
    set -e
    work="$(mktemp -d)"
    echo "python=$(command -v python)"
    nextflow -version | grep -q "version" && echo "nextflow=ok"
    nf-test version | grep -qi "nf-test" && echo "nf_test=ok"
    snakemake --version >/dev/null && echo "snakemake_ver=ok"
    cat > "${work}/Snakefile" <<'\''EOF'\''
rule all:
    output: "result.txt"
    shell: "echo workflow-smk-ok > {output}"
EOF
    snakemake --snakefile "${work}/Snakefile" --directory "${work}" --cores 1 >/dev/null 2>&1
    [ "$(cat "${work}/result.txt")" = "workflow-smk-ok" ] && echo "snakemake_run=ok"
' 2>/dev/null)

has() { printf '%s\n' "${out}" | grep -qxF "$1"; }

has "python=/opt/conda/bin/python" \
    && pass "the session's Python is still the Jupyter environment's" \
    || fail "the session's Python is still the Jupyter environment's"
has "nextflow=ok" && pass "nextflow runs offline" || fail "nextflow runs offline"
has "nf_test=ok" && pass "nf-test runs" || fail "nf-test runs"
has "snakemake_ver=ok" && pass "snakemake runs" || fail "snakemake runs"
has "snakemake_run=ok" && pass "snakemake executes a workflow rule" || fail "snakemake executes a workflow rule"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "workflow-engines smoke: all checks passed"
else
    echo "workflow-engines smoke: ${FAILED} check(s) failed; output:"
    printf '%s\n' "${out}" | sed 's/^/        /'
fi
exit "${FAILED}"
