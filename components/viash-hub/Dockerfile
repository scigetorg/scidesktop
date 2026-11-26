# syntax=docker/dockerfile:1
# Curated Viash Hub & OpenPipelines workflow catalog (/etc/scidesktop/viash-hub/catalog.json)
# and the `viash-catalog` CLI (/usr/local/bin/viash-catalog) for discovering
# curated Viash Hub workflows, printing rootless-Apptainer/Slurm Nextflow commands,
# and scaffolding reproducible Viash components (including wrapping existing
# SCIGET/neurocontainers images). Optional component; copied into genomicsdesktop.

ARG UBUNTU_IMAGE

FROM ${UBUNTU_IMAGE} AS rootfs
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs \
    && chmod 0755 /rootfs/usr/local/bin/viash-catalog \
    && install -d -m 0755 /rootfs/opt/scidesktop/manifest.d \
    && printf '{"catalog_sha256": "%s", "cli_sha256": "%s"}\n' \
        "$(sha256sum /rootfs/etc/scidesktop/viash-hub/catalog.json | cut -d ' ' -f 1)" \
        "$(sha256sum /rootfs/usr/local/bin/viash-catalog | cut -d ' ' -f 1)" \
        > /rootfs/opt/scidesktop/manifest.d/viash-hub.json

FROM scratch AS component
COPY --from=rootfs /rootfs/ /

# On the OS layer with workflow-engines (viash, nextflow, scidesktop.config)
# and jupyter-env's Python (/opt/conda). Runs offline: verifies catalog schema,
# CLI subcommands, component scaffolding (native + OCI container bridge),
# viash test, viash build (executable + nextflow) and offline Nextflow execution.
FROM os AS test
COPY --from=workflow-engines / /
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    set -euo pipefail \
    && export PATH="/opt/conda/bin:${PATH}" \
    && HOME="$(mktemp -d)" && export HOME && cd "${HOME}" \
    && trap 'rm -rf "${HOME}"' EXIT \
    && viash-catalog list | grep -q '^openpipelines' \
    && viash-catalog list --domain genomics | grep -q '^biobox' \
    && viash-catalog info openpipelines | grep -q 'openpipelines-bio/openpipeline' \
    && viash-catalog run-cmd openpipelines qc/qc --slurm | grep -q -- '-profile apptainer,slurm' \
    && viash-catalog json | /opt/conda/bin/python3 -c 'import json, sys; d = json.load(sys.stdin); assert d["schemaVersion"] == 1 and len(d["packages"]) >= 4' \
    && viash-catalog init count_lines --dir "${HOME}/count_lines" --lang python \
        --image ghcr.io/scigetorg/scidesktop:latest \
    && grep -q 'image: ghcr.io/scigetorg/scidesktop:latest' "${HOME}/count_lines/config.vsh.yaml" \
    && viash test "${HOME}/count_lines/config.vsh.yaml" --engine native \
    && viash build "${HOME}/count_lines/config.vsh.yaml" --engine native --runner nextflow \
        --output "${HOME}/nf_mod" \
    && printf 'seq1\nseq2\nseq3\n' > "${HOME}/sample.txt" \
    && NXF_OFFLINE=true NXF_SYNTAX_PARSER=v1 nextflow run "${HOME}/nf_mod/main.nf" \
        -c /etc/scidesktop/nextflow/scidesktop.config -profile apptainer \
        -work-dir "${HOME}/nf_work" \
        --id s1 --input "${HOME}/sample.txt" --output counted.txt --publish_dir "${HOME}/nf_out" \
    && grep -qxF 'component=count_lines' "${HOME}/nf_out/counted.txt" \
    && grep -qxF 'lines=3' "${HOME}/nf_out/counted.txt"
