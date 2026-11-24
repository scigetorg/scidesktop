# syntax=docker/dockerfile:1
# micromamba, the installer the conda-based components (jupyter-env, selkies) build
# their environments with. Version and checksums come from docker-bake.hcl.

ARG UBUNTU_IMAGE

FROM ${UBUNTU_IMAGE} AS build
ARG MICROMAMBA_VERSION
ARG MICROMAMBA_SHA256_AMD64
ARG MICROMAMBA_SHA256_ARM64
ARG TARGETARCH
ARG APT_CACHE_ID
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y curl ca-certificates
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    --mount=type=bind,from=components,source=fetch,target=/usr/local/bin/fetch \
    : "${MICROMAMBA_VERSION:?}" "${MICROMAMBA_SHA256_AMD64:?}" "${MICROMAMBA_SHA256_ARM64:?}" \
    && platform="$(target-arch conda)" \
    && sha256="MICROMAMBA_SHA256_${TARGETARCH^^}" \
    && install -d -m 0755 /out/usr/local/bin \
    && fetch "https://github.com/mamba-org/micromamba-releases/releases/download/${MICROMAMBA_VERSION}/micromamba-${platform}" \
        "${!sha256}" /out/usr/local/bin/micromamba \
    && chmod 0755 /out/usr/local/bin/micromamba

FROM scratch AS component
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
RUN micromamba --version
