# syntax=docker/dockerfile:1
# The Agent Client Protocol adapters for Codex and Claude Code at
# /opt/acp-adapters, which give Jupyter AI's chat a persona for each
# (docs/jupyter-ai.md). They are Node.js programs, so the component brings a
# Node.js of its own: the upstream release, checked against the checksum in
# docker-bake.hcl, used by nothing else. The adapters are installed from the
# lock beside this file, without the copy of its agent each package would
# bring: they run the agents of the coding-agents component. Not part of the
# base image; images with the coding agents copy it (docs/images.md).

# Versions and checksums come from docker-bake.hcl; the adapters' versions
# are in package.json and package-lock.json (./lock).
ARG UBUNTU_IMAGE

FROM ${UBUNTU_IMAGE} AS build
ARG NODE_VERSION
ARG NODE_SHA256_AMD64
ARG NODE_SHA256_ARM64
ARG TARGETARCH
ARG APT_CACHE_ID
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y curl ca-certificates xz-utils
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    --mount=type=bind,from=components,source=fetch,target=/usr/local/bin/fetch \
    : "${NODE_VERSION:?}" "${NODE_SHA256_AMD64:?}" "${NODE_SHA256_ARM64:?}" \
    && sha256="NODE_SHA256_${TARGETARCH^^}" \
    && fetch "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-$(target-arch node).tar.xz" \
        "${!sha256}" /tmp/node.tar.xz \
    && mkdir -p /opt/node && tar -xJf /tmp/node.tar.xz -C /opt/node --strip-components=1 --no-same-owner \
    && rm /tmp/node.tar.xz \
    && test "$(/opt/node/bin/node --version)" = "v${NODE_VERSION}"
COPY package.json package-lock.json /opt/acp-adapters/lib/
# npm installs exactly the lock, checks each package's integrity hash, and
# runs no install script. --omit=optional leaves out the per-platform
# packages, which are the adapters' own copies of Codex and Claude Code
# (about 250 MB each).
RUN cd /opt/acp-adapters/lib \
    && PATH="/opt/node/bin:${PATH}" npm ci --omit=optional --ignore-scripts --no-audit --no-fund \
    && modules=/opt/acp-adapters/lib/node_modules \
    && test -f "${modules}/@agentclientprotocol/codex-acp/dist/index.js" \
    && test -f "${modules}/@agentclientprotocol/claude-agent-acp/dist/index.js" \
    && if ls -d "${modules}"/@openai/codex-* "${modules}"/@anthropic-ai/claude-agent-sdk-*-* 2>/dev/null | grep .; then \
        echo "an adapter brought its own copy of its agent" >&2; exit 1; fi \
    && find "${modules}" -type f \( -name '*.map' -o -name '*.d.ts' \) -delete \
    # Only the interpreter of the Node.js release is kept: npm was needed
    # here, not in the image.
    && install -D -m 0755 /opt/node/bin/node /opt/acp-adapters/node/bin/node \
    && install -m 0644 /opt/node/LICENSE /opt/acp-adapters/node/LICENSE \
    && chmod -R a+rX,go-w /opt/acp-adapters \
    && install -d -m 0755 /out/manifest \
    && version() { sed -n 's/^  "version": "\(.*\)",$/\1/p' "${modules}/@agentclientprotocol/$1/package.json"; } \
    && printf '{"node": "%s", "codex-acp": "%s", "claude-agent-acp": "%s"}\n' \
        "${NODE_VERSION}" "$(version codex-acp)" "$(version claude-agent-acp)" > /out/manifest/acp-adapters.json \
    && cat /out/manifest/acp-adapters.json

# Integration files from rootfs/ (the two commands and their links) at their
# image paths, readable and without group or other write permission whatever
# the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /opt/acp-adapters /opt/acp-adapters
COPY --from=build /out/manifest/ /opt/scidesktop/manifest.d/

# On the OS layer with the agents the adapters run, and the Jupyter
# environment, whose Jupyter AI looks for them.
FROM os AS test
COPY --from=coding-agents / /
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,from=tests,source=acp-adapters-check.py,target=/tmp/acp-adapters-check.py \
    HOME=/tmp/acp-home PATH="/opt/conda/bin:${PATH}" /opt/conda/bin/python /tmp/acp-adapters-check.py
