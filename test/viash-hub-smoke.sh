#!/bin/bash
# End-to-end check of an image that copies the viash-hub component.
#
#   ./test/viash-hub-smoke.sh [image]
#
# Verifies offline (`--network none`):
#   - `viash-catalog list`, `info`, `run-cmd`, `json` read the curated catalog
#     and enforce architecture compatibility + package flag validation
#   - `viash-catalog init --image` exports the exact supplied container via
#     Viash's Nextflow `directives.container` (not `<name>:latest`)
#   - `viash-catalog init --force` refuses to overwrite symlink targets
#   - `viash test --engine native`, `viash run`, and `viash build --runner nextflow`
#     compile and run cleanly offline with `/etc/scidesktop/nextflow/scidesktop.config`

set -uo pipefail

IMAGE="${1:-genomicsdesktop}"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

echo "viash-hub smoke: ${IMAGE}"
out=$(docker run --rm --network none -e SCIDESKTOP_SLURM=no "${IMAGE}" bash -lc '
    set -euo pipefail
    work="$(mktemp -d)"
    cd "${work}"

    viash-catalog list | grep -q "^openpipelines" && echo "list_openpipelines=ok"
    viash-catalog list --domain genomics | grep -q "^biobox" && echo "list_biobox=ok"
    viash-catalog info openpipelines --arch amd64 | grep -q "openpipelines-bio/openpipeline" && echo "info=ok"
    viash-catalog run-cmd openpipelines multiomics/process_samples --slurm --arch amd64 \
        | grep -q -- "NXF_SYNTAX_PARSER=v1 nextflow run openpipelines-bio/openpipeline.*-c /etc/scidesktop/nextflow/scidesktop.config -profile apptainer,slurm" \
        && echo "run_cmd=ok"
    if ! viash-catalog run-cmd openpipelines qc/qc --arch arm64 >/dev/null 2>&1 \
        && viash-catalog run-cmd openpipelines qc/qc --arch arm64 --allow-unsupported-arch >/dev/null 2>"${work}/arm.err" \
        && grep -qi "warning:" "${work}/arm.err"; then
        echo "arch_guard=ok"
    fi
    viash-catalog json | /opt/conda/bin/python3 -c '\''
import json, sys
d = json.load(sys.stdin)
assert d["schemaVersion"] == 1
ids = {p["id"] for p in d["packages"]}
assert {"openpipelines", "openpipelines-spatial", "biobox", "openproblems-batch-integration"} <= ids, ids
assert all(p["architectures"] for p in d["packages"])
print("json=ok")
'\''

    # Symlink overwrite protection
    mkdir -p "${work}/sym_dir"
    echo keep > "${work}/outside.txt"
    ln -s "${work}/outside.txt" "${work}/sym_dir/config.vsh.yaml"
    if ! viash-catalog init sym_comp --dir "${work}/sym_dir" --force >/dev/null 2>&1 \
        && [ "$(cat "${work}/outside.txt")" = "keep" ]; then
        echo "symlink_guard=ok"
    fi

    # Container-bridged scaffold must export the exact supplied container in Nextflow main.nf
    viash-catalog init bridged_qc --dir "${work}/bridged_qc" --lang python \
        --image ghcr.io/scigetorg/scidesktop:latest >/dev/null
    viash build "${work}/bridged_qc/config.vsh.yaml" --runner nextflow \
        --output "${work}/nf_bridged" >/dev/null 2>&1
    if grep -q "\"container\" : \"ghcr.io/scigetorg/scidesktop:latest\"" "${work}/nf_bridged/main.nf" \
        && ! grep -q "\"container\" : \"bridged_qc:latest\"" "${work}/nf_bridged/main.nf"; then
        echo "init_bridge=ok"
    fi

    # Native Python component: unit-test, run, and execute Nextflow VDSL3 module offline
    viash-catalog init seq_qc --dir "${work}/seq_qc" --lang python >/dev/null
    viash test "${work}/seq_qc/config.vsh.yaml" --engine native >/dev/null 2>&1 \
        && echo "viash_test=ok"
    printf ">s1\nACGT\n" > "${work}/in.fa"
    viash run "${work}/seq_qc/config.vsh.yaml" --engine native -- \
        --input "${work}/in.fa" --output "${work}/run_out.txt" >/dev/null 2>&1
    grep -qxF "component=seq_qc" "${work}/run_out.txt" \
        && grep -qxF "lines=2" "${work}/run_out.txt" \
        && echo "viash_run=ok"

    viash build "${work}/seq_qc/config.vsh.yaml" --engine native --runner nextflow \
        --output "${work}/nf_seq_qc" >/dev/null 2>&1
    NXF_OFFLINE=true NXF_SYNTAX_PARSER=v1 nextflow run "${work}/nf_seq_qc/main.nf" \
        -c "${SCIDESKTOP_NEXTFLOW_CONFIG}" -profile apptainer \
        -work-dir "${work}/nf_work" \
        --id s1 --input "${work}/in.fa" --output qc.txt --publish_dir "${work}/nf_out" >/dev/null 2>&1
    grep -qxF "component=seq_qc" "${work}/nf_out/qc.txt" \
        && grep -qxF "lines=2" "${work}/nf_out/qc.txt" \
        && echo "viash_nextflow=ok"
' 2>&1)

has() { printf '%s\n' "${out}" | grep -qxF "$1"; }

has "list_openpipelines=ok" && pass "viash-catalog lists openpipelines" || fail "viash-catalog lists openpipelines"
has "list_biobox=ok" && pass "viash-catalog filters genomics domain (biobox)" || fail "viash-catalog filters genomics domain (biobox)"
has "info=ok" && pass "viash-catalog info shows openpipelines metadata" || fail "viash-catalog info shows openpipelines metadata"
has "run_cmd=ok" && pass "viash-catalog run-cmd emits Apptainer+Slurm Nextflow command" || fail "viash-catalog run-cmd emits Apptainer+Slurm Nextflow command"
has "arch_guard=ok" && pass "viash-catalog rejects unsupported arch by default and warns on override" || fail "viash-catalog rejects unsupported arch by default and warns on override"
has "json=ok" && pass "viash-catalog json emits valid v1 catalog with architectures" || fail "viash-catalog json emits valid v1 catalog with architectures"
has "symlink_guard=ok" && pass "viash-catalog init --force refuses symlink overwrite" || fail "viash-catalog init --force refuses symlink overwrite"
has "init_bridge=ok" && pass "viash-catalog init --image exports exact container directive in Nextflow main.nf" || fail "viash-catalog init --image exports exact container directive in Nextflow main.nf"
has "viash_test=ok" && pass "viash test runs scaffolded component offline" || fail "viash test runs scaffolded component offline"
has "viash_run=ok" && pass "viash run executes scaffolded component offline" || fail "viash run executes scaffolded component offline"
has "viash_nextflow=ok" && pass "viash build -> nextflow run executes offline with scidesktop.config" || fail "viash build -> nextflow run executes offline with scidesktop.config"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "viash-hub smoke: all checks passed"
else
    echo "viash-hub smoke: ${FAILED} check(s) failed; output:"
    printf '%s\n' "${out}" | sed 's/^/        /'
fi
exit "${FAILED}"
