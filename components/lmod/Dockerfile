# syntax=docker/dockerfile:1
# Lmod built from its release tarball on plain Ubuntu of the OS layer's
# release, so an OS package update (a snapshot bump) does not rebuild it or
# change its layer. Runtime needs lua5.4, lua-posix, lua-filesystem and tcl
# from the OS layer; the test runs it there.

# Versions come from docker-bake.hcl.
ARG UBUNTU_IMAGE

FROM ${UBUNTU_IMAGE} AS build
ARG LMOD_VERSION
ARG LMOD_SHA256
ARG TARGETARCH
ARG APT_CACHE_ID
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=private \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=private \
    apt-get update && apt-get install --no-install-recommends -y \
        gcc make bc pkg-config liblua5.4-dev tcl-dev \
        lua5.4 lua-posix lua-filesystem tcl curl ca-certificates
RUN --mount=type=bind,from=components,source=fetch,target=/usr/local/bin/fetch \
    : "${LMOD_VERSION:?}" "${LMOD_SHA256:?}" \
    && fetch "https://github.com/TACC/Lmod/archive/refs/tags/${LMOD_VERSION}.tar.gz" \
        "${LMOD_SHA256}" /tmp/lmod.tar.gz \
    && mkdir -p /tmp/lmod && tar -xzf /tmp/lmod.tar.gz -C /tmp/lmod --strip-components=1 \
    && cd /tmp/lmod \
    && ./configure --prefix=/opt/apps --with-spiderCacheDir=/var/cache/lmod \
    && make install \
    && /opt/apps/lmod/lmod/libexec/lmod --version 2>&1 | grep -F "${LMOD_VERSION}" \
    && install -d -m 0755 /out/manifest \
    && printf '{"lmod": "%s"}\n' "${LMOD_VERSION}" > /out/manifest/lmod.json \
    # Start-up hook for the Jupyter server: just the variables jupyterlmod and
    # Lmod's commands need, taken from Lmod's own init. Sourcing the full init
    # there would also export BASH_ENV and the module functions, making every
    # later bash process the server starts load Lmod again.
    && install -d -m 0755 /out/hooks \
    && { printf '%s\n' '# Generated at build time from Lmod'"'"'s init (components/lmod/Dockerfile).' \
           '# Sourced by start.sh: Lmod'"'"'s variables for the Jupyter server (jupyterlmod).'; \
         env -i HOME=/root PATH=/usr/bin:/bin bash -c '. /opt/apps/lmod/lmod/init/profile >/dev/null 2>&1; \
           for v in LMOD_CMD LMOD_DIR LMOD_PKG LMOD_ROOT MODULESHOME MODULEPATH MODULEPATH_ROOT; do \
             [ -n "${!v:-}" ] || { echo "Lmod init did not set ${v}" >&2; exit 1; }; \
             printf "[ -n \"\${%s:-}\" ] || export %s=%q\n" "${v}" "${v}" "${!v}"; \
           done'; } > /out/hooks/15-lmod.sh \
    && chmod 0644 /out/hooks/15-lmod.sh

# Integration files from rootfs/ (hooks, symlinks, config) at their image paths,
# without group or other write permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs && install -d -m 0755 /rootfs/var/cache/lmod

# Lmod and its shell setup: login shells via /etc/profile.d, other interactive
# shells via /etc/bash.bashrc.d.
FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /opt/apps /opt/apps
COPY --from=build /out/manifest/ /opt/scidesktop/manifest.d/
COPY --from=build /out/hooks/ /usr/local/bin/before-notebook.d/

FROM os AS test
COPY --from=component / /
RUN bash -lc 'module --version 2>&1 | grep -q "Modules based on Lua"' \
    && bash -ic 'type -t module' 2>/dev/null | grep -qx function \
    && bash -c 'source /opt/apps/lmod/lmod/init/bash && module avail 2>&1 | tail -1' \
    # The start-up hook gives the Jupyter server Lmod's environment (jupyterlmod).
    && env -u LMOD_CMD -u BASH_ENV bash -ec '. /usr/local/bin/before-notebook.d/15-lmod.sh; test -x "${LMOD_CMD}"; [ -n "${MODULEPATH}" ]; [ -z "${BASH_ENV:-}" ]; ! declare -F module' \
    && cat /usr/local/bin/before-notebook.d/15-lmod.sh
