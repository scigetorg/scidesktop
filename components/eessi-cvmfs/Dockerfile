# syntax=docker/dockerfile:1
# The EESSI (European Environment for Scientific Software Installations)
# CVMFS repository (software.eessi.io) for the base's CVMFS client:
#   - official domain config & signing key from EESSI/filesystem-layer (SHA-256 verified)
#   - internal-mode repository default hook (19-eessi-cvmfs.sh)
#   - Lmod modulepath provider (65-eessi) exposing EESSI/<version> when mounted
#   - dynamic desktop app launcher hook (32-eessi-apps.sh) exposing base &
#     domain-specific EESSI GUI/CLI launchers when /cvmfs/software.eessi.io is mounted
#   - eessi-launch and eessi-catalog user helpers

ARG UBUNTU_IMAGE

FROM ${UBUNTU_IMAGE} AS rootfs
ARG TARGETARCH
ARG APT_CACHE_ID
ARG EESSI_CVMFS_CONFIG_VERSION
ARG EESSI_CVMFS_CONFIG_SHA256
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y ca-certificates curl openssl
COPY rootfs/ /rootfs/
RUN tmp="$(mktemp -d)" \
    && trap 'rm -rf "${tmp}"' EXIT \
    && curl -fsSL -o "${tmp}/cvmfs-config-eessi.tar" \
        "https://github.com/EESSI/filesystem-layer/releases/download/v${EESSI_CVMFS_CONFIG_VERSION:?}/cvmfs-config-eessi-${EESSI_CVMFS_CONFIG_VERSION}.tar" \
    && printf '%s  %s\n' "${EESSI_CVMFS_CONFIG_SHA256:?}" "${tmp}/cvmfs-config-eessi.tar" | sha256sum -c - \
    && tar -xf "${tmp}/cvmfs-config-eessi.tar" -C "${tmp}" \
    && install -d -m 0755 /rootfs/etc/cvmfs/domain.d /rootfs/etc/cvmfs/keys/eessi.io /rootfs/opt/scidesktop/manifest.d \
    && install -m 0644 "${tmp}/etc/cvmfs/domain.d/eessi.io.conf" /rootfs/etc/cvmfs/domain.d/eessi.io.conf \
    && install -m 0644 "${tmp}/etc/cvmfs/keys/eessi.io/eessi.io.pub" /rootfs/etc/cvmfs/keys/eessi.io/eessi.io.pub \
    && key=/rootfs/etc/cvmfs/keys/eessi.io/eessi.io.pub \
    && fingerprint="$(openssl pkey -pubin -in "${key}" -outform DER | sha256sum | cut -d ' ' -f 1)" \
    && [ "${#fingerprint}" -eq 64 ] \
    && chmod -R a+rX,go-w /rootfs \
    && chmod 0755 \
        /rootfs/etc/scidesktop/modulepath.d/65-eessi \
        /rootfs/usr/local/bin/eessi-launch \
        /rootfs/usr/local/bin/eessi-catalog \
        /rootfs/usr/local/bin/before-notebook.d/19-eessi-cvmfs.sh \
        /rootfs/usr/local/bin/before-notebook.d/32-eessi-apps.sh \
    && printf '{"repository": "software.eessi.io", "config_version": "%s", "default_stack": "2025.06", "public_key_sha256": "%s"}\n' \
        "${EESSI_CVMFS_CONFIG_VERSION}" "${fingerprint}" \
        > /rootfs/opt/scidesktop/manifest.d/eessi-cvmfs.json

FROM scratch AS component
COPY --from=rootfs /rootfs/ /

FROM os AS test
COPY --from=component / /
RUN --mount=type=bind,source=test.sh,target=/tmp/test.sh bash /tmp/test.sh
