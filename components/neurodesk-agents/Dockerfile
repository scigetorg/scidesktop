# syntax=docker/dockerfile:1
# Neurodesk's defaults for the coding agents, supplied only through the
# coding-agents component's extension points (docs/coding-agents.md): the
# agents' instructions for working with Neurodesk tools, and the Neurodesk
# model provider for OpenCode. No key or token is in it. It holds no agent:
# an image copies coding-agents as well. Not part of the base image.

ARG UBUNTU_IMAGE

# Integration files from rootfs/ at their image paths, readable and without
# group or other write permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY rootfs/ /rootfs/
# The manifest identifies the instructions and the provider by content, so a
# change to either shows in an image's manifest.
RUN chmod -R a+rX,go-w /rootfs \
    && install -d -m 0755 /rootfs/opt/scidesktop/manifest.d \
    && printf '{"instructions_sha256": "%s", "opencode_provider_sha256": "%s"}\n' \
        "$(sha256sum /rootfs/opt/neurodesk-agents/AGENTS.md | cut -d ' ' -f 1)" \
        "$(sha256sum /rootfs/opt/neurodesk-agents/opencode.json | cut -d ' ' -f 1)" \
        > /rootfs/opt/scidesktop/manifest.d/neurodesk-agents.json

FROM scratch AS component
COPY --from=rootfs /rootfs/ /

# On the OS layer with the agents it configures and the hook that gives a
# home its defaults (startup).
FROM os AS test
COPY --from=coding-agents / /
COPY --from=startup / /
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,source=test.sh,target=/tmp/test.sh bash /tmp/test.sh
