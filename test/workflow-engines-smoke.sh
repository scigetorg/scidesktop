#!/bin/bash
# End-to-end check of an image that copies the workflow-engines component.
#
#   ./test/workflow-engines-smoke.sh [image]
#
# Verifies Nextflow (offline fat executable), nf-test, Viash, and Snakemake
# (plus Slurm execution and `/etc/scidesktop/nextflow/scidesktop.config`)
# execute real workflows cleanly with `--network none` without altering the
# session's default Python.

set -uo pipefail

IMAGE="${1:-scidesktop}"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

echo "workflow-engines smoke: ${IMAGE}"
out=$(docker run --rm --network none -e SCIDESKTOP_SLURM=no "${IMAGE}" bash -lc '
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

    vsh_ver="$(viash --version 2>&1)"
    printf "%s\n" "${vsh_ver}" | grep -qi "viash" && echo "viash_ver=ok"
    [ "${SCIDESKTOP_NEXTFLOW_CONFIG:-}" = "/etc/scidesktop/nextflow/scidesktop.config" ] && echo "nf_config_env=ok"
    [ -n "${NXF_APPTAINER_CACHEDIR:-}" ] && echo "nxf_apptainer_cache=ok"
    mkdir -p "${work}/vsh"
    cat > "${work}/vsh/config.vsh.yaml" <<'\''VSH'\''
name: greet
arguments:
  - name: --name
    type: string
    default: world
  - name: --output
    type: file
    direction: output
    required: true
resources:
  - type: bash_script
    path: script.sh
engines:
  - type: native
runners:
  - type: executable
  - type: nextflow
VSH
    cat > "${work}/vsh/script.sh" <<'\''SH'\''
#!/bin/bash
set -euo pipefail
echo "viash-${par_name}" > "${par_output}"
SH
    viash run "${work}/vsh/config.vsh.yaml" -- --name native --output "${work}/vsh-native.txt" >/dev/null 2>&1
    [ "$(cat "${work}/vsh-native.txt")" = "viash-native" ] && echo "viash_run=ok"
    viash build "${work}/vsh/config.vsh.yaml" --runner nextflow --output "${work}/vsh-nf" >/dev/null 2>&1
    NXF_OFFLINE=true NXF_SYNTAX_PARSER=v1 nextflow run "${work}/vsh-nf/main.nf" \
        -c "${SCIDESKTOP_NEXTFLOW_CONFIG}" -profile apptainer \
        -work-dir "${work}/vsh-nf-work" \
        --id s1 --name nextflow --output out.txt --publish_dir "${work}/vsh-nf-out" >/dev/null 2>&1
    [ "$(cat "${work}/vsh-nf-out/out.txt")" = "viash-nextflow" ] && echo "viash_nf_run=ok"

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

# Submit a real Snakemake rule to the bundled session Slurm queue using squeue
# status polling (matching the session queue accounting_storage/none config).
slurm_out=$(docker run --rm "${IMAGE}" bash -lc '
    set -euo pipefail
    work="$(mktemp -d)"
    /opt/slurm/bin/slurm-session wait >/dev/null 2>&1
    cat > "${work}/Snakefile.slurm" <<'\''SMK'\''
rule all:
    output: "slurm-result.txt"
    shell: "echo slurm-smk-ok > {output}"
SMK
    snakemake --snakefile "${work}/Snakefile.slurm" --directory "${work}" \
        --executor slurm --slurm-status-command squeue \
        --slurm-init-seconds-before-status-checks 2 \
        --default-resources slurm_partition=scidesktop runtime=5 mem_mb=256 \
        --jobs 1 >/dev/null 2>&1
    [ "$(cat "${work}/slurm-result.txt")" = "slurm-smk-ok" ] && echo "snakemake_slurm_run=ok"

    cat > "${work}/slurm.nf" <<'\''NF'\''
process SLURM_HELLO {
    output:
    path "nf-slurm.txt"
    script:
    """
    echo "nextflow-slurm-ok job=\${SLURM_JOB_ID:?SLURM_JOB_ID missing}" > nf-slurm.txt
    """
}
workflow {
    SLURM_HELLO()
}
NF
    cd "${work}"
    nf_slurm_log="$(NXF_OFFLINE=true nextflow run "${work}/slurm.nf" \
        -c "${SCIDESKTOP_NEXTFLOW_CONFIG}" -profile slurm \
        -work-dir "${work}/nf-slurm-work" 2>&1)" || {
        printf "%s\n" "${nf_slurm_log}"
        exit 1
    }
    nf_slurm_out="$(find "${work}/nf-slurm-work" -type f -name nf-slurm.txt -exec cat {} + 2>/dev/null || true)"
    if grep -qE "^nextflow-slurm-ok job=[0-9]+$" <<<"${nf_slurm_out}"; then
        echo "nextflow_slurm_run=ok"
    else
        printf "nf_slurm_out=%s\n%s\n" "${nf_slurm_out}" "${nf_slurm_log}"
    fi
' 2>&1)

has() { printf '%s\n%s\n' "${out}" "${slurm_out}" | grep -qxF "$1"; }

has "python=/opt/conda/bin/python" \
    && pass "the session's Python is still the Jupyter environment's" \
    || fail "the session's Python is still the Jupyter environment's"
has "nextflow_ver=ok" && pass "nextflow version works offline" || fail "nextflow version works offline"
has "nextflow_run=ok" && pass "nextflow executes a pipeline with --network none" || fail "nextflow executes a pipeline with --network none"
has "nf_test_ver=ok" && pass "nf-test version works offline" || fail "nf-test version works offline"
has "nf_test_run=ok" && pass "nf-test executes a pipeline test with --network none" || fail "nf-test executes a pipeline test with --network none"
has "viash_ver=ok" && pass "viash version works offline" || fail "viash version works offline"
has "nf_config_env=ok" && pass "SCIDESKTOP_NEXTFLOW_CONFIG points to shared Nextflow config" || fail "SCIDESKTOP_NEXTFLOW_CONFIG points to shared Nextflow config"
has "nxf_apptainer_cache=ok" && pass "NXF_APPTAINER_CACHEDIR is set by default" || fail "NXF_APPTAINER_CACHEDIR is set by default"
has "viash_run=ok" && pass "viash runs a native component offline" || fail "viash runs a native component offline"
has "viash_nf_run=ok" && pass "viash builds a Nextflow VDSL3 module that runs offline with scidesktop.config" || fail "viash builds a Nextflow VDSL3 module that runs offline with scidesktop.config"
has "snakemake_ver=ok" && pass "snakemake runs" || fail "snakemake runs"
has "snakemake_slurm=ok" && pass "snakemake Slurm executor plugin is installed" || fail "snakemake Slurm executor plugin is installed"
has "snakemake_run=ok" && pass "snakemake executes a workflow rule" || fail "snakemake executes a workflow rule"
has "snakemake_slurm_run=ok" && pass "snakemake executes a rule on the session Slurm queue (--slurm-status-command squeue)" || fail "snakemake executes a rule on the session Slurm queue (--slurm-status-command squeue)"
has "nextflow_slurm_run=ok" && pass "nextflow executes a process on the session Slurm queue (-profile slurm)" || fail "nextflow executes a process on the session Slurm queue (-profile slurm)"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "workflow-engines smoke: all checks passed"
else
    echo "workflow-engines smoke: ${FAILED} check(s) failed; output:"
    printf '%s\n%s\n' "${out}" "${slurm_out}" | sed 's/^/        /'
fi
exit "${FAILED}"
