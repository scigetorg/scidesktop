# syntax=docker/dockerfile:1
# Apptainer built from source on plain Ubuntu of the OS layer's release: the
# same release gives the same library ABI, and building off the OS layer means
# an OS package update (a snapshot bump) does not rebuild Apptainer or change
# its layer. The test runs it on the real OS layer and fails on any missing
# library. Built --without-suid: scidesktop runs Apptainer strictly through
# unprivileged user namespaces and never ships the SUID-root starter binary.

# Versions come from docker-bake.hcl.
ARG APPTAINER_GO_VERSION
ARG UBUNTU_IMAGE
FROM docker.io/library/golang:${APPTAINER_GO_VERSION} AS go

FROM ${UBUNTU_IMAGE} AS build
ARG APPTAINER_VERSION
ARG APPTAINER_SHA256
ARG APPTAINER_GRPC_VERSION
# Go modules raised past the release's own pins for their security fixes, in
# Apptainer and in the gocryptfs source it bundles.
ARG APPTAINER_CRYPTO_VERSION
ARG APPTAINER_JOSE_VERSION
ARG APPTAINER_COMPRESS_VERSION
ARG APPTAINER_GO_ARCHIVE_VERSION
ARG TARGETARCH
ARG APT_CACHE_ID
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=private \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=private \
    apt-get update && apt-get install --no-install-recommends -y \
        autoconf automake build-essential ca-certificates cryptsetup curl git libattr1-dev \
        libfuse3-dev liblzo2-dev liblz4-dev liblzma-dev libprotobuf-c-dev \
        libseccomp-dev libsubid-dev libtalloc-dev libtool libzstd-dev \
        pkg-config zlib1g-dev
COPY --from=go /usr/local/go /usr/local/go
ENV PATH=/usr/local/go/bin:${PATH} GOTOOLCHAIN=local
RUN --mount=type=bind,from=components,source=fetch,target=/usr/local/bin/fetch \
    --mount=type=cache,target=/root/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    : "${APPTAINER_VERSION:?}" "${APPTAINER_SHA256:?}" "${APPTAINER_GRPC_VERSION:?}" \
      "${APPTAINER_CRYPTO_VERSION:?}" "${APPTAINER_JOSE_VERSION:?}" \
      "${APPTAINER_COMPRESS_VERSION:?}" "${APPTAINER_GO_ARCHIVE_VERSION:?}" \
    && fetch \
        "https://github.com/apptainer/apptainer/releases/download/v${APPTAINER_VERSION}/apptainer-${APPTAINER_VERSION}.tar.gz" \
        "${APPTAINER_SHA256}" /tmp/apptainer.tar.gz \
    && mkdir -p /tmp/apptainer \
    && tar -xzf /tmp/apptainer.tar.gz --strip-components=1 -C /tmp/apptainer \
    && rm -f /tmp/apptainer.tar.gz \
    && cd /tmp/apptainer \
    && go get "google.golang.org/grpc@v${APPTAINER_GRPC_VERSION}" \
        "golang.org/x/crypto@v${APPTAINER_CRYPTO_VERSION}" \
        "github.com/go-jose/go-jose/v4@v${APPTAINER_JOSE_VERSION}" \
        "github.com/klauspost/compress@v${APPTAINER_COMPRESS_VERSION}" \
        "github.com/moby/go-archive@v${APPTAINER_GO_ARCHIVE_VERSION}" \
    && go mod tidy && go mod vendor \
    && test "$(go list -m -f '{{.Version}}' google.golang.org/grpc)" = "v${APPTAINER_GRPC_VERSION}" \
    && test "$(go list -m -f '{{.Version}}' golang.org/x/crypto)" = "v${APPTAINER_CRYPTO_VERSION}" \
    && test "$(go list -m -f '{{.Version}}' github.com/go-jose/go-jose/v4)" = "v${APPTAINER_JOSE_VERSION}" \
    && test "$(go list -m -f '{{.Version}}' github.com/klauspost/compress)" = "v${APPTAINER_COMPRESS_VERSION}" \
    && test "$(go list -m -f '{{.Version}}' github.com/moby/go-archive)" = "v${APPTAINER_GO_ARCHIVE_VERSION}" \
    && ./scripts/download-dependencies \
    && archive="$(echo gocryptfs_v*_src-deps.tar.gz)" && test -f "${archive}" \
    && tar -xf "${archive}" \
    && (cd "${archive%.tar.gz}" \
        && go get "golang.org/x/crypto@v${APPTAINER_CRYPTO_VERSION}" \
        && go mod tidy && go mod vendor \
        && test "$(go list -m -f '{{.Version}}' golang.org/x/crypto)" = "v${APPTAINER_CRYPTO_VERSION}") \
    && tar -czf "${archive}" "${archive%.tar.gz}" && rm -rf "${archive%.tar.gz}" \
    && ./scripts/compile-dependencies \
    && printf '%s\n' "${APPTAINER_VERSION}" > VERSION \
    && ./mconfig --prefix=/opt/apptainer --without-suid \
    && make -C builddir \
    && make -C builddir install \
    && ./scripts/install-dependencies \
    && rm -rf /opt/apptainer/libexec/apptainer/cni \
    && sed -i 's/^allow setuid = yes/allow setuid = no/' /opt/apptainer/etc/apptainer/apptainer.conf \
    && install -d -m 0755 /out/manifest \
    && printf '{"apptainer": "%s"}\n' "$(/opt/apptainer/bin/apptainer --version | awk '{print $NF}')" \
        > /out/manifest/apptainer.json

# Integration files from rootfs/ (hooks, symlinks, config) at their image paths,
# without group or other write permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

# Apptainer, its command links and its startup hook (10-apptainer).
FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /opt/apptainer /opt/apptainer
COPY --from=build /out/manifest/ /opt/scidesktop/manifest.d/

FROM os AS test
COPY --from=component / /
RUN set -e \
    && apptainer --version && singularity --version \
    && test -x /usr/local/bin/before-notebook.d/10-apptainer \
    && test ! -e /opt/apptainer/libexec/apptainer/bin/starter-suid \
    && grep -qx 'allow setuid = no' /opt/apptainer/etc/apptainer/apptainer.conf \
    && test -x /opt/apptainer/libexec/apptainer/bin/proot \
    && test -x /opt/apptainer/libexec/apptainer/bin/mksquashfs \
    && missing=$(find /opt/apptainer -type f -perm -u+x -exec sh -c '[ "$(head -c 4 "$1" | tail -c 3)" = ELF ] && ldd "$1" 2>/dev/null | grep "not found" | sed "s|^|$1: |"' _ {} \; ) \
    && { [ -z "${missing}" ] || { echo "${missing}"; exit 1; }; }
