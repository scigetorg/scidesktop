# syntax=docker/dockerfile:1
# The NiiVue VS Code extension (korbinianeckstein.niivue) for imaging desktops,
# installed at build time into code-server's system extensions folder
# (/usr/local/share/code-server/extensions). Extensions only: an image copies
# code-server as well. Not part of the base image; domain images copy it
# (docs/images.md).

# Versions and checksums come from docker-bake.hcl.
ARG UBUNTU_IMAGE

FROM ${UBUNTU_IMAGE} AS build
ARG TARGETARCH
ARG APT_CACHE_ID
ARG VSCODE_NIIVUE_VERSION
ARG VSCODE_NIIVUE_SHA256
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y curl ca-certificates jq unzip
RUN --mount=type=bind,from=components,source=code-server/install-extension,target=/usr/local/bin/install-extension \
    install-extension KorbinianEckstein niivue "${VSCODE_NIIVUE_VERSION:?}" "${VSCODE_NIIVUE_SHA256:?}" /out \
    && install -d -m 0755 /out/opt/scidesktop/manifest.d \
    && printf '{"korbinianeckstein.niivue": "%s"}\n' "${VSCODE_NIIVUE_VERSION}" \
        > /out/opt/scidesktop/manifest.d/vscode-niivue.json

FROM scratch AS component
COPY --from=build /out/ /

FROM os AS test
COPY --from=code-server / /
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,from=tests,source=vscode-extensions-check.py,target=/tmp/vscode-extensions-check.py \
    /opt/conda/bin/python /tmp/vscode-extensions-check.py vscode-niivue
