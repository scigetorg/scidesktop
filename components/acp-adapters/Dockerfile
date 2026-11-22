# syntax=docker/dockerfile:1
# The Agent Client Protocol adapters for Codex and Claude Code at
# /opt/acp-adapters, which give Jupyter AI's chat a persona for each
# (docs/jupyter-ai.md). The adapters are installed from the lock beside this
# file without the copy of its agent each package would bring (they run the
# agents of components/coding-agents) and share Node.js from
# components/code-server (/opt/code-server/lib/node) rather than shipping a
# second 127 MB Node binary.

# Versions come from docker-bake.hcl; the adapters' versions are in
# package.json and package-lock.json (./lock).
ARG NODE_VERSION
ARG UBUNTU_IMAGE

FROM docker.io/library/node:${NODE_VERSION}-bookworm-slim AS build
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY package.json package-lock.json /opt/acp-adapters/lib/
# npm installs exactly the lock, checks each package's integrity hash, and
# runs no install script. --omit=optional leaves out the per-platform
# packages, which are the adapters' own copies of Codex and Claude Code
# (about 250 MB each).
RUN --mount=type=cache,target=/root/.npm \
    cd /opt/acp-adapters/lib \
    && npm ci --omit=optional --ignore-scripts --no-audit --no-fund \
    && modules=/opt/acp-adapters/lib/node_modules \
    && test -f "${modules}/@agentclientprotocol/codex-acp/dist/index.js" \
    && test -f "${modules}/@agentclientprotocol/claude-agent-acp/dist/index.js" \
    && if ls -d "${modules}"/@openai/codex-* "${modules}"/@anthropic-ai/claude-agent-sdk-*-* 2>/dev/null | grep .; then \
        echo "an adapter brought its own copy of its agent" >&2; exit 1; fi \
    && find "${modules}" -type f \( -name '*.map' -o -name '*.d.ts' \) -delete \
    && chmod -R a+rX,go-w /opt/acp-adapters \
    && install -d -m 0755 /out/manifest \
    && version() { sed -n 's/^  "version": "\(.*\)",$/\1/p' "${modules}/@agentclientprotocol/$1/package.json"; } \
    && printf '{"codex-acp": "%s", "claude-agent-acp": "%s"}\n' \
        "$(version codex-acp)" "$(version claude-agent-acp)" > /out/manifest/acp-adapters.json \
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

# On the OS layer with the agents and shared Node runtime the adapters use,
# plus the Jupyter environment, whose Jupyter AI looks for them.
FROM os AS test
COPY --from=code-server / /
COPY --from=coding-agents / /
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,from=tests,source=acp-adapters-check.py,target=/tmp/acp-adapters-check.py \
    HOME=/tmp/acp-home PATH="/opt/conda/bin:${PATH}" /opt/conda/bin/python /tmp/acp-adapters-check.py
