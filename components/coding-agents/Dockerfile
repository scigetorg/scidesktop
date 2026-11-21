# syntax=docker/dockerfile:1
# The Codex, Claude Code and OpenCode command-line agents at /opt/coding-agents,
# on PATH for terminals. Each is its upstream's release binary for the build's
# architecture, checked against the checksum in docker-bake.hcl. Not part of
# the base image; domain images copy it (docs/images.md).

# Versions and checksums come from docker-bake.hcl.
ARG UBUNTU_IMAGE

FROM ${UBUNTU_IMAGE} AS build
ARG TARGETARCH
ARG APT_CACHE_ID
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y curl ca-certificates
# `fetch <url> <sha256> <file>`: a release file, refused unless its checksum matches.
RUN printf '%s\n' '#!/bin/bash' 'set -euo pipefail' \
        'curl -fsSL --retry 5 --retry-delay 5 --retry-connrefused -o "$3" "$1"' \
        'echo "$2  $3" | sha256sum -c - >/dev/null' > /usr/local/bin/fetch \
    && chmod 0755 /usr/local/bin/fetch \
    && install -d -m 0755 /opt/coding-agents/bin /opt/coding-agents/licenses /out/versions

# One agent per stage, so updating one downloads only that one.
FROM build AS codex
ARG CODEX_VERSION
ARG CODEX_SHA256_AMD64
ARG CODEX_SHA256_ARM64
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    : "${CODEX_VERSION:?}" "${CODEX_SHA256_AMD64:?}" "${CODEX_SHA256_ARM64:?}" \
    && sha256="CODEX_SHA256_${TARGETARCH^^}" \
    && release="codex-$(target-arch uname)-unknown-linux-musl" \
    && fetch "https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/${release}.tar.gz" \
        "${!sha256}" /tmp/codex.tar.gz \
    && tar -xzf /tmp/codex.tar.gz -C /tmp --no-same-owner "${release}" \
    && install -m 0755 "/tmp/${release}" /opt/coding-agents/bin/codex \
    && test "$(/opt/coding-agents/bin/codex --version)" = "codex-cli ${CODEX_VERSION}" \
    && for file in LICENSE NOTICE; do \
        curl -fsSL --retry 5 -o "/opt/coding-agents/licenses/codex-${file}" \
            "https://raw.githubusercontent.com/openai/codex/rust-v${CODEX_VERSION}/${file}"; \
    done \
    && grep -q "Apache License" /opt/coding-agents/licenses/codex-LICENSE \
    && printf '%s' "${CODEX_VERSION}" > /out/versions/codex

FROM build AS claude-code
ARG CLAUDE_CODE_VERSION
ARG CLAUDE_CODE_SHA256_AMD64
ARG CLAUDE_CODE_SHA256_ARM64
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    : "${CLAUDE_CODE_VERSION:?}" "${CLAUDE_CODE_SHA256_AMD64:?}" "${CLAUDE_CODE_SHA256_ARM64:?}" \
    && sha256="CLAUDE_CODE_SHA256_${TARGETARCH^^}" \
    && fetch "https://downloads.claude.ai/claude-code-releases/${CLAUDE_CODE_VERSION}/linux-$(target-arch node)/claude" \
        "${!sha256}" /tmp/claude \
    && install -m 0755 /tmp/claude /opt/coding-agents/bin/claude \
    && HOME=/tmp/home /opt/coding-agents/bin/claude --version | grep -qxF "${CLAUDE_CODE_VERSION} (Claude Code)" \
    # Not open source: the notice says whose terms apply (docs/coding-agents.md).
    && curl -fsSL --retry 5 -o /opt/coding-agents/licenses/claude-code-LICENSE.md \
        "https://raw.githubusercontent.com/anthropics/claude-code/v${CLAUDE_CODE_VERSION}/LICENSE.md" \
    && grep -q "Anthropic" /opt/coding-agents/licenses/claude-code-LICENSE.md \
    && printf '%s' "${CLAUDE_CODE_VERSION}" > /out/versions/claude-code

FROM build AS opencode
ARG OPENCODE_VERSION
ARG OPENCODE_SHA256_AMD64
ARG OPENCODE_SHA256_ARM64
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    : "${OPENCODE_VERSION:?}" "${OPENCODE_SHA256_AMD64:?}" "${OPENCODE_SHA256_ARM64:?}" \
    && sha256="OPENCODE_SHA256_${TARGETARCH^^}" \
    && package="cli-linux-$(target-arch node)" \
    && fetch "https://registry.npmjs.org/@opencode/${package}/-/${package}-${OPENCODE_VERSION}.tgz" \
        "${!sha256}" /tmp/opencode.tgz \
    && tar -xzf /tmp/opencode.tgz -C /tmp --no-same-owner package/bin/opencode \
    && install -m 0755 /tmp/package/bin/opencode /opt/coding-agents/bin/opencode \
    && test "$(HOME=/tmp/home /opt/coding-agents/bin/opencode --version)" = "opencode v${OPENCODE_VERSION}" \
    && curl -fsSL --retry 5 -o /opt/coding-agents/licenses/opencode-LICENSE \
        "https://raw.githubusercontent.com/anomalyco/opencode/v${OPENCODE_VERSION}/LICENSE" \
    && grep -q "MIT License" /opt/coding-agents/licenses/opencode-LICENSE \
    && printf '%s' "${OPENCODE_VERSION}" > /out/versions/opencode

# Integration files from rootfs/ (command links, home defaults) at their image
# paths, readable and without group or other write permission whatever the
# checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs
RUN --mount=type=bind,from=codex,source=/out/versions,target=/versions/codex \
    --mount=type=bind,from=claude-code,source=/out/versions,target=/versions/claude-code \
    --mount=type=bind,from=opencode,source=/out/versions,target=/versions/opencode \
    install -d -m 0755 /rootfs/opt/scidesktop/manifest.d \
    && printf '{"codex": "%s", "claude-code": "%s", "opencode": "%s"}\n' \
        "$(cat /versions/codex/codex)" "$(cat /versions/claude-code/claude-code)" \
        "$(cat /versions/opencode/opencode)" > /rootfs/opt/scidesktop/manifest.d/coding-agents.json

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=codex /opt/coding-agents /opt/coding-agents
COPY --from=claude-code /opt/coding-agents /opt/coding-agents
COPY --from=opencode /opt/coding-agents /opt/coding-agents

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,source=test.sh,target=/tmp/test.sh bash /tmp/test.sh
