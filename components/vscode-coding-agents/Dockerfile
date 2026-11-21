# syntax=docker/dockerfile:1
# The Claude Code and Codex VS Code extensions (anthropic.claude-code,
# openai.chatgpt), kept separate from vscode-core because each carries its own
# copy of its agent (~1.5 GB together). Installed at build time into
# code-server's system extensions folder (/usr/local/share/code-server/extensions).
# Extensions only: an image copies code-server as well. Not part of the base
# image; domain images copy it (docs/images.md).

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
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y curl ca-certificates jq unzip
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    --mount=type=bind,from=components,source=fetch,target=/usr/local/bin/fetch \
    --mount=type=bind,from=components,source=code-server/install-extension,target=/usr/local/bin/install-extension \
    platform="linux-$(target-arch node)" \
    && claude="VSCODE_CLAUDE_CODE_SHA256_${TARGETARCH^^}" \
    && chatgpt="VSCODE_CHATGPT_SHA256_${TARGETARCH^^}" \
    && install-extension Anthropic claude-code "${VSCODE_CLAUDE_CODE_VERSION:?}" "${!claude:?}" /out "${platform}" \
    && install-extension openai chatgpt "${VSCODE_CHATGPT_VERSION:?}" "${!chatgpt:?}" /out "${platform}" \
    && install -d -m 0755 /out/opt/scidesktop/manifest.d \
    && printf '{"anthropic.claude-code": "%s", "openai.chatgpt": "%s"}\n' \
        "${VSCODE_CLAUDE_CODE_VERSION}" "${VSCODE_CHATGPT_VERSION}" \
        > /out/opt/scidesktop/manifest.d/vscode-coding-agents.json

FROM scratch AS component
COPY --from=build /out/ /

FROM os AS test
COPY --from=code-server / /
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,from=tests,source=vscode-extensions-check.py,target=/tmp/vscode-extensions-check.py \
    /opt/conda/bin/python /tmp/vscode-extensions-check.py vscode-coding-agents
