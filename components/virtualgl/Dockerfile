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
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=private \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=private \
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
    && install -d -m 0755 /out/opt /out/usr/lib /out/usr/local/bin /out/opt/scidesktop/manifest.d \
    && cp -a /tmp/vgl/opt/VirtualGL /out/opt/VirtualGL \
    # VirtualGL's faker preload libraries live in /usr/lib in the upstream .deb
    # so vglrun's bare LD_PRELOAD=libdlfaker.so:libvglfaker.so resolves via ld.so.
    # Upstream ships libvglfaker-opencl.so on amd64 only.
    && libs="libdlfaker.so libgefaker.so libvglfaker.so libvglfaker-nodl.so" \
    && if [ "${TARGETARCH}" = "amd64" ]; then libs="${libs} libvglfaker-opencl.so"; fi \
    && for lib in ${libs}; do \
         cp -a "/tmp/vgl/usr/lib/${lib}" "/out/usr/lib/${lib}" || exit 1; \
       done \
    && ln -s /opt/VirtualGL/bin/vglrun /out/usr/local/bin/vglrun \
    && ln -s /opt/VirtualGL/bin/eglinfo /out/usr/local/bin/vgl-eglinfo \
    && printf '{"virtualgl": "%s"}\n' "${VIRTUALGL_VERSION}" > /out/opt/scidesktop/manifest.d/virtualgl.json \
    && chmod -R a+rX,go-w /out \
    && rm -rf /tmp/virtualgl.deb /tmp/vgl

FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /out/ /

FROM os AS test
ARG TARGETARCH
COPY --from=component / /
USER ${NB_UID}
RUN set -eu \
    && test -x /usr/local/bin/vglrun \
    && test -x /usr/local/bin/vgl-eglinfo \
    && test -r /usr/local/bin/before-notebook.d/13-virtualgl-env.sh \
    && libs="libdlfaker.so libgefaker.so libvglfaker.so libvglfaker-nodl.so" \
    && if [ "${TARGETARCH}" = "amd64" ]; then libs="${libs} libvglfaker-opencl.so"; fi \
    && for lib in ${libs}; do \
         test -r "/usr/lib/${lib}" || exit 1; \
       done \
    && ldd_out="$(ldd /usr/lib/libvglfaker.so /usr/lib/libdlfaker.so /opt/VirtualGL/bin/glxspheres64 2>&1)" \
    && case "${ldd_out}" in *"not found"*) echo "${ldd_out}" >&2; exit 1 ;; esac \
    && out="$(vglrun /bin/true 2>&1)" \
    && case "${out}" in *"cannot be preloaded"*|*ERROR*) echo "${out}" >&2; exit 1 ;; esac \
    && test -r /opt/scidesktop/manifest.d/virtualgl.json \
    # Startup hook: no-op without a GPU (including CPU-only containers where
    # host /proc/driver/nvidia/version is visible), resolves real NVIDIA
    # primary DRM card via by-path (ignoring virtual GPUs), falls back to
    # sysfs vendor matching without by-path, falls back to "egl" only when
    # NVIDIA GPU device nodes are exposed, and preserves an explicit VGL_DISPLAY.
    && mock="$(mktemp -d)" \
    && env -u VGL_DISPLAY -u APPTAINERENV_VGL_DISPLAY \
        SCIDESKTOP_SYS_ROOT="${mock}/sys" SCIDESKTOP_DEV_ROOT="${mock}/dev" SCIDESKTOP_PROC_ROOT="${mock}/proc" \
        bash -ec '. /usr/local/bin/before-notebook.d/13-virtualgl-env.sh; [ -z "${VGL_DISPLAY:-}" ] && [ -z "${APPTAINERENV_VGL_DISPLAY:-}" ]' \
    && mkdir -p "${mock}/sys/bus/pci/drivers/nvidia/0000:00:05.0" "${mock}/proc/driver/nvidia" \
    && touch "${mock}/proc/driver/nvidia/version" \
    && env -u VGL_DISPLAY -u APPTAINERENV_VGL_DISPLAY \
        SCIDESKTOP_SYS_ROOT="${mock}/sys" SCIDESKTOP_DEV_ROOT="${mock}/dev" SCIDESKTOP_PROC_ROOT="${mock}/proc" \
        bash -ec '. /usr/local/bin/before-notebook.d/13-virtualgl-env.sh; [ -z "${VGL_DISPLAY:-}" ] && [ -z "${APPTAINERENV_VGL_DISPLAY:-}" ]' \
    && mkdir -p "${mock}/dev/dri/by-path" \
    && touch "${mock}/dev/dri/card0" "${mock}/dev/dri/card1" \
    && ln -s ../card0 "${mock}/dev/dri/by-path/pci-0000:00:02.0-card" \
    && ln -s ../card1 "${mock}/dev/dri/by-path/pci-0000:00:05.0-card" \
    && env -u VGL_DISPLAY -u APPTAINERENV_VGL_DISPLAY \
        SCIDESKTOP_SYS_ROOT="${mock}/sys" SCIDESKTOP_DEV_ROOT="${mock}/dev" SCIDESKTOP_PROC_ROOT="${mock}/proc" \
        bash -ec '. /usr/local/bin/before-notebook.d/13-virtualgl-env.sh; [ "${VGL_DISPLAY}" = "'"${mock}/dev/dri/card1"'" ] && [ "${APPTAINERENV_VGL_DISPLAY}" = "${VGL_DISPLAY}" ]' \
    && rm -rf "${mock}/dev/dri/by-path" "${mock}/sys/bus" \
    && mkdir -p "${mock}/sys/class/drm/card0/device" "${mock}/sys/class/drm/card1/device" \
    && echo "0x1af4" > "${mock}/sys/class/drm/card0/device/vendor" \
    && echo "0x10de" > "${mock}/sys/class/drm/card1/device/vendor" \
    && env -u VGL_DISPLAY -u APPTAINERENV_VGL_DISPLAY \
        SCIDESKTOP_SYS_ROOT="${mock}/sys" SCIDESKTOP_DEV_ROOT="${mock}/dev" SCIDESKTOP_PROC_ROOT="${mock}/proc" \
        bash -ec '. /usr/local/bin/before-notebook.d/13-virtualgl-env.sh; [ "${VGL_DISPLAY}" = "'"${mock}/dev/dri/card1"'" ] && [ "${APPTAINERENV_VGL_DISPLAY}" = "${VGL_DISPLAY}" ]' \
    && rm -rf "${mock}/sys/class" "${mock}/dev/dri" \
    && touch "${mock}/dev/nvidiactl" "${mock}/dev/nvidia0" \
    && env -u VGL_DISPLAY -u APPTAINERENV_VGL_DISPLAY \
        SCIDESKTOP_SYS_ROOT="${mock}/sys" SCIDESKTOP_DEV_ROOT="${mock}/dev" SCIDESKTOP_PROC_ROOT="${mock}/proc" \
        bash -ec '. /usr/local/bin/before-notebook.d/13-virtualgl-env.sh; [ "${VGL_DISPLAY}" = egl ] && [ "${APPTAINERENV_VGL_DISPLAY}" = egl ]' \
    && env -u APPTAINERENV_VGL_DISPLAY VGL_DISPLAY=egl0 \
        SCIDESKTOP_SYS_ROOT="${mock}/sys" SCIDESKTOP_DEV_ROOT="${mock}/dev" SCIDESKTOP_PROC_ROOT="${mock}/proc" \
        bash -ec '. /usr/local/bin/before-notebook.d/13-virtualgl-env.sh; [ "${VGL_DISPLAY}" = egl0 ] && [ "${APPTAINERENV_VGL_DISPLAY}" = egl0 ]' \
    && rm -rf "${mock}"
