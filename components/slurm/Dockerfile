# syntax=docker/dockerfile:1
# A Slurm queue for one session: a controller and a worker for this container
# alone, started beside the notebook server as the notebook user
# (/opt/slurm/bin/slurm-session). Slurm itself is the OS layer's packages
# (components/os-ubuntu/packages/slurm.txt). This component is what runs it
# without root: its configuration, its start hook, and a small library that
# keeps the daemons on loopback.

ARG UBUNTU_IMAGE

# Built on plain Ubuntu of the OS layer's release: the library uses only the
# C library.
FROM ${UBUNTU_IMAGE} AS build
ARG TARGETARCH
ARG APT_CACHE_ID
ARG NB_UID
ARG NB_GID
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y gcc libc6-dev
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
    # The manifest identifies the start logic by content; the Slurm version
    # is the OS layer's.
    && printf '{"session_sha256": "%s", "loopback_bind_sha256": "%s"}\n' \
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
# stops, with no privilege a JupyterHub pod lacks.
FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,source=test.sh,target=/tmp/test.sh bash /tmp/test.sh
