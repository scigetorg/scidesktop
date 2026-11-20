# syntax=docker/dockerfile:1
# The VS Code extensions neurodesk/neurodesktop gives its users, for every
# user of an image with code-server: installed at build time into the folder
# code-server reads as its system extensions
# (/usr/local/share/code-server/extensions), each at a pinned version and
# checked against its checksum. neurodesktop downloads them into each home at
# every start; here nothing is downloaded at start and nothing is copied into
# a home. Extensions only: an image copies code-server as well. Not part of
# the base image (docs/images.md).

# Versions and checksums come from docker-bake.hcl.
ARG UBUNTU_IMAGE

FROM ${UBUNTU_IMAGE} AS build
ARG TARGETARCH
ARG APT_CACHE_ID
ARG VSCODE_CLAUDE_CODE_VERSION
ARG VSCODE_CLAUDE_CODE_SHA256_AMD64
ARG VSCODE_CLAUDE_CODE_SHA256_ARM64
ARG VSCODE_CHATGPT_VERSION
ARG VSCODE_CHATGPT_SHA256_AMD64
ARG VSCODE_CHATGPT_SHA256_ARM64
ARG VSCODE_PYTHON_VERSION
ARG VSCODE_PYTHON_SHA256_AMD64
ARG VSCODE_PYTHON_SHA256_ARM64
ARG VSCODE_JUPYTER_VERSION
ARG VSCODE_JUPYTER_SHA256
ARG VSCODE_GITHUB_PR_VERSION
ARG VSCODE_GITHUB_PR_SHA256
ARG VSCODE_CSV_VERSION
ARG VSCODE_CSV_SHA256
ARG VSCODE_NIIVUE_VERSION
ARG VSCODE_NIIVUE_SHA256
ARG VSCODE_SLURM_VERSION
ARG VSCODE_SLURM_SHA256
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y curl ca-certificates unzip
# code-server's install-extension downloads from Open VSX, checks the checksum
# and unpacks. Three extensions are published per platform; the others are one
# file for every architecture.
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    --mount=type=bind,from=components,source=code-server/install-extension,target=/usr/local/bin/install-extension \
    platform="linux-$(target-arch node)" \
    && claude="VSCODE_CLAUDE_CODE_SHA256_${TARGETARCH^^}" \
    && chatgpt="VSCODE_CHATGPT_SHA256_${TARGETARCH^^}" \
    && python="VSCODE_PYTHON_SHA256_${TARGETARCH^^}" \
    && install-extension Anthropic claude-code "${VSCODE_CLAUDE_CODE_VERSION:?}" "${!claude:?}" /out "${platform}" \
    && install-extension openai chatgpt "${VSCODE_CHATGPT_VERSION:?}" "${!chatgpt:?}" /out "${platform}" \
    && install-extension ms-python python "${VSCODE_PYTHON_VERSION:?}" "${!python:?}" /out "${platform}" \
    && install-extension ms-toolsai jupyter "${VSCODE_JUPYTER_VERSION:?}" "${VSCODE_JUPYTER_SHA256:?}" /out \
    && install-extension GitHub vscode-pull-request-github "${VSCODE_GITHUB_PR_VERSION:?}" "${VSCODE_GITHUB_PR_SHA256:?}" /out \
    && install-extension ReprEng csv "${VSCODE_CSV_VERSION:?}" "${VSCODE_CSV_SHA256:?}" /out \
    && install-extension KorbinianEckstein niivue "${VSCODE_NIIVUE_VERSION:?}" "${VSCODE_NIIVUE_SHA256:?}" /out \
    && install-extension xy-sss slurm--extension "${VSCODE_SLURM_VERSION:?}" "${VSCODE_SLURM_SHA256:?}" /out \
    && install -d -m 0755 /out/opt/scidesktop/manifest.d \
    && printf '{"anthropic.claude-code": "%s", "openai.chatgpt": "%s", "ms-python.python": "%s", "ms-toolsai.jupyter": "%s", "github.vscode-pull-request-github": "%s", "repreng.csv": "%s", "korbinianeckstein.niivue": "%s", "xy-sss.slurm--extension": "%s"}\n' \
        "${VSCODE_CLAUDE_CODE_VERSION}" "${VSCODE_CHATGPT_VERSION}" "${VSCODE_PYTHON_VERSION}" "${VSCODE_JUPYTER_VERSION}" \
        "${VSCODE_GITHUB_PR_VERSION}" "${VSCODE_CSV_VERSION}" "${VSCODE_NIIVUE_VERSION}" "${VSCODE_SLURM_VERSION}" \
        > /out/opt/scidesktop/manifest.d/neurodesk-vscode.json

FROM scratch AS component
COPY --from=build /out/ /

# On the OS layer with code-server, which must accept every extension: each
# is in the folder under the name and version the manifest gives it, and
# says it runs on this code-server's VS Code.
FROM os AS test
COPY --from=code-server / /
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,from=tests,source=vscode-extensions-check.py,target=/tmp/vscode-extensions-check.py \
    /opt/conda/bin/python /tmp/vscode-extensions-check.py neurodesk-vscode
