# syntax=docker/dockerfile:1
# A Slurm queue for one session: a controller and a worker for this container
# alone, started beside the notebook server as the notebook user
# (/opt/slurm/bin/slurm-session). Slurm is built from source into /opt/slurm,
# with only what the session's configuration uses: its own authentication
# (auth/slurm, which needs libjwt; no munge) and JSON output, without cgroups,
# PAM, an accounting database, Lua or hwloc. libjwt and its jansson and libb64,
# which the OS layer lacks, ship in /opt/slurm/lib/deps. Commands and daemons are linked
# into /usr/local/bin and /usr/local/sbin.
# The component also carries the configuration links, the start hook, and a
# small library that keeps the daemons on loopback.

ARG UBUNTU_IMAGE

# Built on plain Ubuntu of the OS layer's release, against libraries the OS
# layer has (C library, json-c, OpenSSL) plus the bundled libjwt.
FROM ${UBUNTU_IMAGE} AS build
ARG SLURM_TAG
ARG SLURM_SHA256
ARG TARGETARCH
ARG APT_CACHE_ID
ARG NB_UID
ARG NB_GID
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y \
        gcc libc6-dev make pkg-config python3 binutils curl ca-certificates \
        libjwt-dev libjson-c-dev patchelf
RUN --mount=type=bind,from=components,source=fetch,target=/usr/local/bin/fetch \
    : "${SLURM_TAG:?}" "${SLURM_SHA256:?}" \
    # Tag slurm-25-11-9-1 is release 25.11.9.
    && version="$(sed -E 's/^slurm-([0-9]+)-([0-9]+)-([0-9]+)-[0-9]+$/\1.\2.\3/' <<<"${SLURM_TAG}")" \
    && fetch "https://github.com/SchedMD/slurm/archive/refs/tags/${SLURM_TAG}.tar.gz" \
        "${SLURM_SHA256}" /tmp/slurm.tar.gz \
    && mkdir -p /tmp/slurm && tar -xzf /tmp/slurm.tar.gz -C /tmp/slurm --strip-components=1 \
    && cd /tmp/slurm \
    # Optional features are found only when their development files are
    # installed: here libjwt and json-c.
    && ./configure --prefix=/opt/slurm --sysconfdir=/etc/slurm --disable-debug \
        --without-munge --disable-pam --disable-x11 \
        LDFLAGS="-Wl,-rpath,/opt/slurm/lib/deps" >/tmp/configure.log \
    && grep -q '^#define HAVE_JWT' config.h \
    && grep -q '^#define HAVE_JSON' config.h \
    && make -j"$(nproc)" >/tmp/make.log \
    && make install >/tmp/install.log \
    && rm -rf /opt/slurm/include /opt/slurm/share \
    && install -d -m 0755 /opt/slurm/lib/deps \
    && cp -L /usr/lib/*/libjwt.so.2 /usr/lib/*/libjansson.so.4 /usr/lib/*/libb64.so.0d /opt/slurm/lib/deps/ \
    && patchelf --set-rpath '$ORIGIN' /opt/slurm/lib/deps/libjwt.so.2 \
    && find /opt/slurm \( -name '*.a' -o -name '*.la' \) -delete \
    && { find /opt/slurm -type f \( -perm -u+x -o -name '*.so*' \) -exec strip --strip-unneeded {} + 2>/dev/null || true; } \
    && /opt/slurm/sbin/slurmctld -V | grep -qx "slurm ${version}" \
    && test -r /opt/slurm/lib/slurm/auth_slurm.so \
    && test -r /opt/slurm/lib/slurm/select_cons_tres.so \
    && test -r /opt/slurm/lib/slurm/sched_backfill.so \
    && install -d -m 0755 /out/opt /out/usr/local/bin /out/usr/local/sbin \
    && cp -a /opt/slurm /out/opt/slurm \
    && for f in /opt/slurm/bin/*; do ln -s "${f}" "/out/usr/local/bin/$(basename "${f}")"; done \
    && for f in /opt/slurm/sbin/*; do ln -s "${f}" "/out/usr/local/sbin/$(basename "${f}")"; done \
    && echo "${version}" > /tmp/slurm-version
COPY src/loopback_bind.c /src/loopback_bind.c
COPY rootfs/opt/slurm/bin/slurm-session /src/slurm-session
RUN : "${NB_UID:?}" "${NB_GID:?}" \
    && install -d -m 0755 /out/opt/slurm/lib /out/opt/scidesktop/manifest.d \
    && gcc -shared -fPIC -O2 -Wall -Werror -o /out/opt/slurm/lib/loopback_bind.so /src/loopback_bind.c \
    && chmod 0755 /out/opt/slurm/lib/loopback_bind.so \
    # Where Slurm's daemons keep their sockets (the paths are fixed in Slurm)
    # and where this session's configuration, state and logs go: the
    # notebook user's, so nothing needs root at start.
    && install -d -m 0775 -o "${NB_UID}" -g "${NB_GID}" /out/run/slurm /out/run/slurmctld \
    && printf '{"slurm": "%s", "session_sha256": "%s", "loopback_bind_sha256": "%s"}\n' \
        "$(cat /tmp/slurm-version)" \
        "$(sha256sum /src/slurm-session | cut -d ' ' -f 1)" \
        "$(sha256sum /src/loopback_bind.c | cut -d ' ' -f 1)" \
        > /out/opt/scidesktop/manifest.d/slurm.json

# Integration files from rootfs/ (the start hook, the session script, the
# links from /etc/slurm) at their image paths, readable and without group or
# other write permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /out/ /

# On the OS layer, as the notebook user: a queue starts, runs a job and
# stops, with no privilege a JupyterHub pod lacks. Every Slurm binary finds
# its libraries there.
FROM os AS test
COPY --from=component / /
RUN missing=$(find /opt/slurm -type f \( -perm -u+x -o -name '*.so*' \) -exec sh -c \
        '[ "$(head -c 4 "$1" | tail -c 3)" = ELF ] && ldd "$1" 2>/dev/null | grep "not found" | sed "s|^|$1: |"' _ {} \;) \
    && { [ -z "${missing}" ] || { echo "${missing}"; exit 1; }; }
USER ${NB_UID}
RUN --mount=type=bind,source=test.sh,target=/tmp/test.sh bash /tmp/test.sh
