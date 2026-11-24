# syntax=docker/dockerfile:1
# OS layer: Ubuntu packages from a dated archive snapshot, locale, and the
# notebook user. Every other component builds on this image or is copied onto it.

# Versions come from docker-bake.hcl.
ARG UBUNTU_IMAGE

# CA bundle for reaching snapshot.ubuntu.com before ca-certificates is
# installed from it. Only the bundle is used, and only during the build.
FROM ${UBUNTU_IMAGE} AS bootstrap-certs
RUN apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Packages from the dated snapshot. Components that compile against the OS build
# FROM this stage (bake target os-ubuntu-build, context "os-build").
FROM ${UBUNTU_IMAGE} AS build
ARG APT_SNAPSHOT
ARG CVMFS_VERSION
ARG CVMFS_SHA256_AMD64
ARG CVMFS_SHA256_ARM64
ARG CVMFS_LIBS_SHA256_AMD64
ARG CVMFS_LIBS_SHA256_ARM64
ARG CVMFS_FUSE3_SHA256_AMD64
ARG CVMFS_FUSE3_SHA256_ARM64
ARG CVMFS_CONFIG_VERSION
ARG CVMFS_CONFIG_NONE_SHA256
ARG NB_USER
ARG NB_UID
ARG NB_GID
ARG TARGETARCH
ARG APT_CACHE_ID
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=bind,from=bootstrap-certs,source=/etc/ssl/certs/ca-certificates.crt,target=/tmp/bootstrap-ca.crt \
    # Only what the install reads, so edits elsewhere in this component (its
    # Dockerfile, rootfs/) do not rebuild the OS layer.
    --mount=type=bind,source=install,target=/tmp/os-ubuntu/install \
    --mount=type=bind,source=packages,target=/tmp/os-ubuntu/packages \
    --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    --mount=type=bind,from=components,source=fetch,target=/usr/local/bin/fetch \
    --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    APT_SNAPSHOT="${APT_SNAPSHOT:?}" CVMFS_VERSION="${CVMFS_VERSION:?}" \
    CVMFS_SHA256_AMD64="${CVMFS_SHA256_AMD64:?}" CVMFS_SHA256_ARM64="${CVMFS_SHA256_ARM64:?}" \
    CVMFS_LIBS_SHA256_AMD64="${CVMFS_LIBS_SHA256_AMD64:?}" CVMFS_LIBS_SHA256_ARM64="${CVMFS_LIBS_SHA256_ARM64:?}" \
    CVMFS_FUSE3_SHA256_AMD64="${CVMFS_FUSE3_SHA256_AMD64:?}" CVMFS_FUSE3_SHA256_ARM64="${CVMFS_FUSE3_SHA256_ARM64:?}" \
    CVMFS_CONFIG_VERSION="${CVMFS_CONFIG_VERSION:?}" CVMFS_CONFIG_NONE_SHA256="${CVMFS_CONFIG_NONE_SHA256:?}" \
    TARGETARCH="${TARGETARCH}" NB_USER="${NB_USER:?}" NB_UID="${NB_UID:?}" NB_GID="${NB_GID:?}" \
    /tmp/os-ubuntu/install

ENV SHELL=/bin/bash \
    NB_USER="${NB_USER}" \
    NB_UID=${NB_UID} \
    NB_GID=${NB_GID} \
    HOME="/home/${NB_USER}" \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8 \
    LANGUAGE=C.UTF-8

# Integration files from rootfs/ (hooks, symlinks, config) at their image paths,
# without group or other write permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R go-w /rootfs

# The runtime OS layer: the snapshot build, the OS's own integration files (CVMFS hook,
# desktop settings), and apt pointed back at the live archive. Components built
# FROM "os-build" are not rebuilt when this stage changes.
FROM build AS os
COPY --link --from=rootfs /rootfs/ /
RUN for f in /etc/apt/sources.list.d/*.live; do mv "${f}" "${f%.live}"; done

# The contract every OS layer must meet, checked by behaviour. `tests` is the
# repository's test/ directory, passed as a named context by docker-bake.hcl.
FROM os AS test
RUN --mount=type=bind,from=tests,source=os-contract.sh,target=/tmp/os-contract.sh \
    bash /tmp/os-contract.sh
