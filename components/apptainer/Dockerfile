# syntax=docker/dockerfile:1
# Apptainer built from source against the OS layer, so it links against the
# libraries it runs with. Built --with-suid: rootfs/.../10-apptainer turns
# the setuid starter on only where user namespaces are unavailable.

# Versions come from docker-bake.hcl.
ARG APPTAINER_GO_VERSION
ARG UBUNTU_IMAGE
FROM docker.io/library/golang:${APPTAINER_GO_VERSION} AS go

FROM os-build AS build
ARG APPTAINER_VERSION
ARG APPTAINER_GRPC_VERSION
# x/crypto is raised past the release's own pin for its security fixes, in
# Apptainer and in the gocryptfs source it bundles.
ARG APPTAINER_CRYPTO_VERSION
ARG TARGETARCH
ARG APT_CACHE_ID
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y \
        autoconf automake build-essential cryptsetup git libattr1-dev \
        libfuse3-dev liblzo2-dev liblz4-dev liblzma-dev libprotobuf-c-dev \
        libseccomp-dev libsubid-dev libtalloc-dev libtool libzstd-dev \
        pkg-config zlib1g-dev
COPY --from=go /usr/local/go /usr/local/go
ENV PATH=/usr/local/go/bin:${PATH} GOTOOLCHAIN=local
RUN --mount=type=cache,target=/root/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    : "${APPTAINER_VERSION:?}" "${APPTAINER_GRPC_VERSION:?}" "${APPTAINER_CRYPTO_VERSION:?}" \
    && git clone --depth 1 --branch "v${APPTAINER_VERSION}" \
        https://github.com/apptainer/apptainer.git /tmp/apptainer \
    && cd /tmp/apptainer \
    && go get "google.golang.org/grpc@v${APPTAINER_GRPC_VERSION}" \
        "golang.org/x/crypto@v${APPTAINER_CRYPTO_VERSION}" \
    && go mod tidy && go mod download \
    && test "$(go list -m -f '{{.Version}}' golang.org/x/crypto)" = "v${APPTAINER_CRYPTO_VERSION}" \
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
    && ./mconfig --prefix=/opt/apptainer --with-suid \
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
RUN chmod -R go-w /rootfs

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
    && test -u /opt/apptainer/libexec/apptainer/bin/starter-suid \
    && grep -qx 'allow setuid = no' /opt/apptainer/etc/apptainer/apptainer.conf \
    && test -x /opt/apptainer/libexec/apptainer/bin/proot \
    && test -x /opt/apptainer/libexec/apptainer/bin/mksquashfs \
    && missing=$(find /opt/apptainer -type f -perm -u+x -exec sh -c '[ "$(head -c 4 "$1" | tail -c 3)" = ELF ] && ldd "$1" 2>/dev/null | grep "not found" | sed "s|^|$1: |"' _ {} \; ) \
    && { [ -z "${missing}" ] || { echo "${missing}"; exit 1; }; }
