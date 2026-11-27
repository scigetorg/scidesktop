# syntax=docker/dockerfile:1
# Core VS Code extensions for scientific desktops (Python, Jupyter, GitHub PRs,
# CSV, Slurm), installed at build time into code-server's system extensions
# folder (/usr/local/share/code-server/extensions), each pinned and checksummed.
# Extensions only: an image copies code-server as well. Not part of the base
# image; domain images copy it (docs/images.md).

# Versions and checksums come from docker-bake.hcl.
ARG UBUNTU_IMAGE

FROM ${UBUNTU_IMAGE} AS build
ARG TARGETARCH
ARG APT_CACHE_ID
ARG VSCODE_PYTHON_VERSION
ARG VSCODE_PYTHON_SHA256_AMD64
ARG VSCODE_PYTHON_SHA256_ARM64
ARG VSCODE_JUPYTER_VERSION
ARG VSCODE_JUPYTER_SHA256
ARG VSCODE_GITHUB_PR_VERSION
ARG VSCODE_GITHUB_PR_SHA256
ARG VSCODE_CSV_VERSION
ARG VSCODE_CSV_SHA256
ARG VSCODE_SLURM_VERSION
ARG VSCODE_SLURM_SHA256
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=private \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=private \
    apt-get update && apt-get install --no-install-recommends -y curl ca-certificates jq unzip
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    --mount=type=bind,from=components,source=fetch,target=/usr/local/bin/fetch \
    --mount=type=bind,from=components,source=code-server/install-extension,target=/usr/local/bin/install-extension \
    platform="linux-$(target-arch node)" \
    && python="VSCODE_PYTHON_SHA256_${TARGETARCH^^}" \
    && install-extension ms-python python "${VSCODE_PYTHON_VERSION:?}" "${!python:?}" /out "${platform}" \
    && install-extension ms-toolsai jupyter "${VSCODE_JUPYTER_VERSION:?}" "${VSCODE_JUPYTER_SHA256:?}" /out \
    && install-extension GitHub vscode-pull-request-github "${VSCODE_GITHUB_PR_VERSION:?}" "${VSCODE_GITHUB_PR_SHA256:?}" /out \
    && install-extension ReprEng csv "${VSCODE_CSV_VERSION:?}" "${VSCODE_CSV_SHA256:?}" /out \
    && install-extension xy-sss slurm--extension "${VSCODE_SLURM_VERSION:?}" "${VSCODE_SLURM_SHA256:?}" /out \
    && install -d -m 0755 /out/opt/scidesktop/manifest.d \
    && printf '{"ms-python.python": "%s", "ms-toolsai.jupyter": "%s", "github.vscode-pull-request-github": "%s", "repreng.csv": "%s", "xy-sss.slurm--extension": "%s"}\n' \
        "${VSCODE_PYTHON_VERSION}" "${VSCODE_JUPYTER_VERSION}" "${VSCODE_GITHUB_PR_VERSION}" \
        "${VSCODE_CSV_VERSION}" "${VSCODE_SLURM_VERSION}" \
        > /out/opt/scidesktop/manifest.d/vscode-core.json

FROM scratch AS component
COPY --from=build /out/ /

FROM os AS test
COPY --from=code-server / /
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,from=tests,source=vscode-extensions-check.py,target=/tmp/vscode-extensions-check.py \
    /opt/conda/bin/python /tmp/vscode-extensions-check.py vscode-core
