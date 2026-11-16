# syntax=docker/dockerfile:1
# Lmod built from its release tarball against the OS layer's Lua. Runtime
# needs lua5.4, lua-posix, lua-filesystem and tcl from the OS layer.

# Versions come from docker-bake.hcl.
ARG UBUNTU_IMAGE

FROM os-build AS build
# Versions come from docker-bake.hcl.
ARG LMOD_VERSION
ARG LMOD_SHA256
ARG TARGETARCH
ARG APT_CACHE_ID
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y \
        gcc make bc pkg-config liblua5.4-dev tcl-dev
RUN : "${LMOD_VERSION:?}" "${LMOD_SHA256:?}" \
    && curl -fsSL --retry 5 --retry-delay 5 --retry-connrefused \
        "https://github.com/TACC/Lmod/archive/refs/tags/${LMOD_VERSION}.tar.gz" -o /tmp/lmod.tar.gz \
    && echo "${LMOD_SHA256}  /tmp/lmod.tar.gz" | sha256sum -c - \
    && mkdir -p /tmp/lmod && tar -xzf /tmp/lmod.tar.gz -C /tmp/lmod --strip-components=1 \
    && cd /tmp/lmod \
    && ./configure --prefix=/opt/apps --with-spiderCacheDir=/var/cache/lmod \
    && make install \
    && /opt/apps/lmod/lmod/libexec/lmod --version 2>&1 | grep -F "${LMOD_VERSION}" \
    && install -d -m 0755 /out/manifest \
    && printf '{"lmod": "%s"}\n' "${LMOD_VERSION}" > /out/manifest/lmod.json

# Integration files from rootfs/ (hooks, symlinks, config) at their image paths,
# without group or other write permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R go-w /rootfs && install -d -m 0755 /rootfs/var/cache/lmod

# Lmod and its shell setup: login shells via /etc/profile.d, other interactive
# shells via /etc/bash.bashrc.d.
FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /opt/apps /opt/apps
COPY --from=build /out/manifest/ /opt/scidesktop/manifest.d/

FROM os AS test
COPY --from=component / /
RUN bash -lc 'module --version 2>&1 | grep -q "Modules based on Lua"' \
    && bash -ic 'type -t module' 2>/dev/null | grep -qx function \
    && bash -c 'source /opt/apps/lmod/lmod/init/bash && module avail 2>&1 | tail -1'
