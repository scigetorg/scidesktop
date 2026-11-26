# syntax=docker/dockerfile:1
# Genomics & Viash defaults for the coding agents, supplied only through the
# coding-agents component's extension points (docs/coding-agents.md): the
# agents' instructions for working with Viash Hub, OpenPipelines, rootless
# Apptainer Nextflow profiles, EESSI bioinformatics modules, and the locked
# genomics Python kernel. No key, token or model is preset. Not part of the
# base image; copied into genomicsdesktop.

ARG UBUNTU_IMAGE

FROM ${UBUNTU_IMAGE} AS rootfs
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs \
    && install -d -m 0755 /rootfs/opt/scidesktop/manifest.d \
    && printf '{"instructions_sha256": "%s"}\n' \
        "$(sha256sum /rootfs/opt/genomics-agents/AGENTS.md | cut -d ' ' -f 1)" \
        > /rootfs/opt/scidesktop/manifest.d/genomics-agents.json

FROM scratch AS component
COPY --from=rootfs /rootfs/ /

FROM os AS test
COPY --from=coding-agents / /
COPY --from=startup / /
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,source=test.sh,target=/tmp/test.sh bash /tmp/test.sh
