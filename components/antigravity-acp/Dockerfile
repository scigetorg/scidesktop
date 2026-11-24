# syntax=docker/dockerfile:1
# Google Antigravity ACP server (agy_acp_server.par + localharness_external)
# at /opt/antigravity-acp, matching T3 Code's embedded antigravityRelease.ts
# table so T3 Code supports Google/Gemini models out of the box without
# downloading ~336 MB into each user's home on first use.
#
# T3 Code's AntigravityInstallation.resolve() discovers agy_acp_server.par on
# PATH, resolves its realpath, and locates the sibling localharness_external.

# Versions and checksums come from docker-bake.hcl.
ARG UBUNTU_IMAGE

FROM ${UBUNTU_IMAGE} AS build
ARG TARGETARCH
ARG APT_CACHE_ID
ARG ANTIGRAVITY_ACP_VERSION
ARG ANTIGRAVITY_ACP_SHA256_AMD64
ARG ANTIGRAVITY_ACP_SHA256_ARM64
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y curl ca-certificates unzip
RUN --mount=type=bind,from=components,source=fetch,target=/usr/local/bin/fetch \
    : "${ANTIGRAVITY_ACP_VERSION:?}" "${ANTIGRAVITY_ACP_SHA256_AMD64:?}" "${ANTIGRAVITY_ACP_SHA256_ARM64:?}" \
    && case "${TARGETARCH}" in \
        amd64) agy_arch=x86_64 ;; \
        arm64) agy_arch=arm64 ;; \
        *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
       esac \
    && sha256="ANTIGRAVITY_ACP_SHA256_${TARGETARCH^^}" \
    && fetch "https://dl.google.com/agy-extensions/releases/linux/agy-acp-server-${ANTIGRAVITY_ACP_VERSION}-linux-${agy_arch}.zip" \
        "${!sha256}" /tmp/antigravity-acp.zip \
    && install -d -m 0755 /out/opt/antigravity-acp /out/usr/local/bin /out/opt/scidesktop/manifest.d \
    && unzip -q /tmp/antigravity-acp.zip -d /out/opt/antigravity-acp \
    && rm -f /tmp/antigravity-acp.zip \
    && test -f /out/opt/antigravity-acp/agy_acp_server.par \
    && test -f /out/opt/antigravity-acp/localharness_external \
    && chmod 0755 /out/opt/antigravity-acp/agy_acp_server.par /out/opt/antigravity-acp/localharness_external \
    && ln -s /opt/antigravity-acp/agy_acp_server.par /out/usr/local/bin/agy_acp_server.par \
    && printf '{"antigravity-acp": "%s"}\n' "${ANTIGRAVITY_ACP_VERSION}" \
        > /out/opt/scidesktop/manifest.d/antigravity-acp.json \
    && chmod -R a+rX,go-w /out

FROM scratch AS component
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,source=test.py,target=/tmp/test.py \
    /opt/conda/bin/python /tmp/test.py
