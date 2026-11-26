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
# architecture guards, malformed override rejection, symlink safety, container
# bridging (`directives.container`), viash test, viash build and offline Nextflow.
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
    && viash-catalog info openpipelines --arch amd64 | grep -q 'openpipelines-bio/openpipeline' \
    && viash-catalog run-cmd openpipelines qc/qc --slurm --arch amd64 | grep -q -- 'NXF_SYNTAX_PARSER=v1 nextflow run openpipelines-bio/openpipeline.*-profile apptainer,slurm' \
    && ! viash-catalog run-cmd openpipelines qc/qc --arch arm64 >/dev/null 2>&1 \
    && viash-catalog run-cmd openpipelines qc/qc --arch arm64 --allow-unsupported-arch 2>"${HOME}/arm_warn.txt" | grep -q -- '-profile apptainer' \
    && grep -qi 'warning:' "${HOME}/arm_warn.txt" \
    && ! viash-catalog run-cmd biobox --slurm --arch amd64 >/dev/null 2>&1 \
    && viash-catalog run-cmd biobox --arch amd64 --revision 0123456789abcdef | grep -q 'git -C biobox checkout 0123456789abcdef' \
    && viash-catalog json | /opt/conda/bin/python3 -c 'import json, sys; d = json.load(sys.stdin); assert d["schemaVersion"] == 1 and len(d["packages"]) >= 4 and all(p["architectures"] for p in d["packages"])' \
    && ! viash-catalog init null --dir "${HOME}/bad_null" >/dev/null 2>&1 \
    && ! viash-catalog init ok_name --dir "${HOME}/bad_img" --image 'bad::ref' >/dev/null 2>&1 \
    && viash-catalog init priv_reg --dir "${HOME}/priv_reg" --image 'registry:5000/team/image:v1' >/dev/null \
    && viash-catalog init ipv6_reg --dir "${HOME}/ipv6_reg" --image '[::1]:5000/team/image:v1' >/dev/null \
    && printf '{"schemaVersion":1,"packages":[{"id":"bad","name":"Bad","kind":"nextflow-workflow","repository":"a/b","version":"v1","domains":["genomics"],"architectures":["amd64"],"description":"x","default_workflow":"missing","workflows":{"w":{"main_script":"a.nf","description":"d"}}}]}\n' > "${HOME}/bad-cat.json" \
    && ! VIASH_CATALOG_FILE="${HOME}/bad-cat.json" viash-catalog list >/dev/null 2>&1 \
    && printf '{"schemaVersion":true,"packages":[]}\n' > "${HOME}/bad-bool.json" \
    && ! VIASH_CATALOG_FILE="${HOME}/bad-bool.json" viash-catalog list >/dev/null 2>&1 \
    && printf '{"schemaVersion":1.0,"packages":[]}\n' > "${HOME}/bad-float.json" \
    && ! VIASH_CATALOG_FILE="${HOME}/bad-float.json" viash-catalog list >/dev/null 2>&1 \
    && printf '\xff\xfe' > "${HOME}/bad-utf8.json" \
    && ! VIASH_CATALOG_FILE="${HOME}/bad-utf8.json" viash-catalog list 2>"${HOME}/utf8.err" \
    && ! grep -q 'Traceback' "${HOME}/utf8.err" \
    && printf '{"schemaVersion":1,"packages":[{"id":"bad","name":"Bad","kind":"nextflow-workflow","repository":"a/b","version":"v1","domains":["genomics"],"architectures":["amd64"],"description":"x","default_workflow":"w","workflows":{"w":{"main_script":"a.nf","architectures":["arm64"],"description":"d"}}}]}\n' > "${HOME}/bad-arch.json" \
    && ! VIASH_CATALOG_FILE="${HOME}/bad-arch.json" viash-catalog list >/dev/null 2>&1 \
    && mkdir -p "${HOME}/sym_test" && echo orig-cfg > "${HOME}/sym_test/config.vsh.yaml" && echo keep > "${HOME}/outside.txt" && ln -s "${HOME}/outside.txt" "${HOME}/sym_test/script.py" \
    && ! viash-catalog init sym_comp --dir "${HOME}/sym_test" --lang python --force >/dev/null 2>&1 \
    && [ "$(cat "${HOME}/sym_test/config.vsh.yaml")" = "orig-cfg" ] \
    && [ "$(cat "${HOME}/outside.txt")" = "keep" ] \
    && viash-catalog init bridged_qc --dir "${HOME}/bridged_qc" --lang python \
        --image ghcr.io/scigetorg/scidesktop:latest \
    && viash test "${HOME}/bridged_qc/config.vsh.yaml" --engine native \
    && viash build "${HOME}/bridged_qc/config.vsh.yaml" --runner nextflow --output "${HOME}/nf_bridged" \
    && grep -q '"container" : "ghcr.io/scigetorg/scidesktop:latest"' "${HOME}/nf_bridged/main.nf" \
    && ! grep -q '"container" : "bridged_qc:latest"' "${HOME}/nf_bridged/main.nf" \
    && viash-catalog init count_lines --dir "${HOME}/count_lines" --lang python \
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
