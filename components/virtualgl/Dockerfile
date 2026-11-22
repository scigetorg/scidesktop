# syntax=docker/dockerfile:1
# VirtualGL for opt-in GPU-accelerated OpenGL rendering via headless EGL
# (`vglrun`, `vgl-eglinfo`), installed into /opt/VirtualGL from upstream
# Debian releases for both amd64 and arm64.

ARG UBUNTU_IMAGE
FROM ${UBUNTU_IMAGE} AS build
ARG TARGETARCH
ARG APT_CACHE_ID
ARG VIRTUALGL_VERSION
ARG VIRTUALGL_SHA256_AMD64
ARG VIRTUALGL_SHA256_ARM64
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y ca-certificates curl
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    --mount=type=bind,from=components,source=fetch,target=/usr/local/bin/fetch \
    arch="$(target-arch deb)" \
    && case "${TARGETARCH}" in \
        amd64) sha="${VIRTUALGL_SHA256_AMD64:?}" ;; \
        arm64) sha="${VIRTUALGL_SHA256_ARM64:?}" ;; \
        *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
       esac \
    && fetch "https://github.com/VirtualGL/virtualgl/releases/download/${VIRTUALGL_VERSION:?}/virtualgl_${VIRTUALGL_VERSION}_${arch}.deb" \
        "${sha}" /tmp/virtualgl.deb \
    && dpkg-deb -x /tmp/virtualgl.deb /tmp/vgl \
    && install -d -m 0755 /out/opt /out/usr/local/bin /out/opt/scidesktop/manifest.d \
    && cp -a /tmp/vgl/opt/VirtualGL /out/opt/VirtualGL \
    && ln -s /opt/VirtualGL/bin/vglrun /out/usr/local/bin/vglrun \
    && ln -s /opt/VirtualGL/bin/eglinfo /out/usr/local/bin/vgl-eglinfo \
    && printf '{"virtualgl": "%s"}\n' "${VIRTUALGL_VERSION}" > /out/opt/scidesktop/manifest.d/virtualgl.json \
    && chmod -R a+rX,go-w /out \
    && rm -rf /tmp/virtualgl.deb /tmp/vgl

FROM scratch AS component
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN test -x /usr/local/bin/vglrun \
    && test -x /usr/local/bin/vgl-eglinfo \
    && /opt/VirtualGL/bin/vglrun -h 2>&1 | grep -qi 'virtualgl\|vglrun' \
    && test -r /opt/scidesktop/manifest.d/virtualgl.json
