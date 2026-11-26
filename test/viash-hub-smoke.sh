#!/bin/bash
# End-to-end check of an image that copies the viash-hub component.
#
#   ./test/viash-hub-smoke.sh [image]
#
# Verifies offline (`--network none`):
#   - `viash-catalog list`, `info`, `run-cmd`, `json` read the curated catalog
#   - `viash-catalog init` scaffolds both a native Python component and an
#     OCI container-bridged (`--image`) Bash component
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
    viash-catalog info openpipelines | grep -q "openpipelines-bio/openpipeline" && echo "info=ok"
    viash-catalog run-cmd openpipelines multiomics/process_samples --slurm \
        | grep -q -- "-c /etc/scidesktop/nextflow/scidesktop.config -profile apptainer,slurm" \
        && echo "run_cmd=ok"
    viash-catalog json | /opt/conda/bin/python3 -c '\''
import json, sys
d = json.load(sys.stdin)
assert d["schemaVersion"] == 1
ids = {p["id"] for p in d["packages"]}
assert {"openpipelines", "openpipelines-spatial", "biobox", "openproblems-batch-integration"} <= ids, ids
print("json=ok")
'\''

    # Scaffold a Python component bridging an existing container image for Nextflow export
    viash-catalog init seq_qc --dir "${work}/seq_qc" --lang python \
        --image ghcr.io/scigetorg/scidesktop:latest >/dev/null
    grep -q "image: ghcr.io/scigetorg/scidesktop:latest" "${work}/seq_qc/config.vsh.yaml" \
        && echo "init_bridge=ok"

    # Unit-test and run via native engine offline
    viash test "${work}/seq_qc/config.vsh.yaml" --engine native >/dev/null 2>&1 \
        && echo "viash_test=ok"
    printf ">s1\nACGT\n" > "${work}/in.fa"
    viash run "${work}/seq_qc/config.vsh.yaml" --engine native -- \
        --input "${work}/in.fa" --output "${work}/run_out.txt" >/dev/null 2>&1
    grep -qxF "component=seq_qc" "${work}/run_out.txt" \
        && grep -qxF "lines=2" "${work}/run_out.txt" \
        && echo "viash_run=ok"

    # Compile to a Nextflow VDSL3 module and execute offline with scidesktop.config
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
has "json=ok" && pass "viash-catalog json emits valid v1 catalog" || fail "viash-catalog json emits valid v1 catalog"
has "init_bridge=ok" && pass "viash-catalog init bridges container image in config.vsh.yaml" || fail "viash-catalog init bridges container image in config.vsh.yaml"
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
