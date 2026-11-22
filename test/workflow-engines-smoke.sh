#!/bin/bash
# End-to-end check of an image that copies the workflow-engines component.
#
#   ./test/workflow-engines-smoke.sh [image]
#
# Verifies Nextflow (offline fat executable), nf-test, and Snakemake (plus its
# Slurm executor plugin) execute real workflows cleanly with `--network none`
# without altering the session's default Python.

set -uo pipefail

IMAGE="${1:-scidesktop}"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

echo "workflow-engines smoke: ${IMAGE}"
out=$(docker run --rm --network none "${IMAGE}" bash -lc '
    set -euo pipefail
    work="$(mktemp -d)"
    cd "${work}"
    echo "python=$(command -v python)"

    nf_ver="$(nextflow -version 2>&1)"
    printf "%s\n" "${nf_ver}" | grep -q "version" && echo "nextflow_ver=ok"

    cat > "${work}/main.nf" <<'\''NF'\''
process HELLO {
    output:
    path "nf-out.txt"
    script:
    """
    echo nextflow-offline-ok > nf-out.txt
    """
}
workflow {
    HELLO()
}
NF
    NXF_OFFLINE=true nextflow run "${work}/main.nf" -work-dir "${work}/nf-work" >/dev/null 2>&1
    grep -rq "nextflow-offline-ok" "${work}/nf-work" && echo "nextflow_run=ok"

    nft_ver="$(nf-test version 2>&1)"
    printf "%s\n" "${nft_ver}" | grep -qi "nf-test" && echo "nf_test_ver=ok"
    cat > "${work}/main.nf.test" <<'\''NFT'\''
nextflow_pipeline {
    name "Offline pipeline test"
    script "main.nf"
    test("Should run offline") {
        when {
            params {}
        }
        then {
            assert workflow.success
        }
    }
}
NFT
    NXF_OFFLINE=true nf-test test "${work}/main.nf.test" >/dev/null 2>&1 && echo "nf_test_run=ok"

    snakemake --version >/dev/null && echo "snakemake_ver=ok"
    snakemake --executor slurm --help >/dev/null 2>&1 && echo "snakemake_slurm=ok"
    cat > "${work}/Snakefile" <<'\''SMK'\''
rule all:
    output: "result.txt"
    shell: "echo workflow-smk-ok > {output}"
SMK
    snakemake --snakefile "${work}/Snakefile" --directory "${work}" --cores 1 >/dev/null 2>&1
    [ "$(cat "${work}/result.txt")" = "workflow-smk-ok" ] && echo "snakemake_run=ok"
' 2>/dev/null)

has() { printf '%s\n' "${out}" | grep -qxF "$1"; }

has "python=/opt/conda/bin/python" \
    && pass "the session's Python is still the Jupyter environment's" \
    || fail "the session's Python is still the Jupyter environment's"
has "nextflow_ver=ok" && pass "nextflow version works offline" || fail "nextflow version works offline"
has "nextflow_run=ok" && pass "nextflow executes a pipeline with --network none" || fail "nextflow executes a pipeline with --network none"
has "nf_test_ver=ok" && pass "nf-test version works offline" || fail "nf-test version works offline"
has "nf_test_run=ok" && pass "nf-test executes a pipeline test with --network none" || fail "nf-test executes a pipeline test with --network none"
has "snakemake_ver=ok" && pass "snakemake runs" || fail "snakemake runs"
has "snakemake_slurm=ok" && pass "snakemake Slurm executor plugin is installed" || fail "snakemake Slurm executor plugin is installed"
has "snakemake_run=ok" && pass "snakemake executes a workflow rule" || fail "snakemake executes a workflow rule"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "workflow-engines smoke: all checks passed"
else
    echo "workflow-engines smoke: ${FAILED} check(s) failed; output:"
    printf '%s\n' "${out}" | sed 's/^/        /'
fi
exit "${FAILED}"
