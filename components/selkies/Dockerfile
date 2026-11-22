# syntax=docker/dockerfile:1
# Selkies in its own interpreter at /opt/selkies. Nothing is installed into
# the system Python. The web client ships inside the wheel.

# Built from the plain Ubuntu image, not the OS layer: the output depends only
# on the lockfiles, so OS updates do not rebuild it or change its layer.
ARG UBUNTU_IMAGE
FROM ${UBUNTU_IMAGE} AS build
ARG TARGETARCH
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get install --no-install-recommends -y ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# A pin changed without ./lock fails here rather than installing the old lock.
RUN --mount=type=bind,from=components,source=check-lock,target=/usr/local/bin/check-lock \
    --mount=type=bind,source=.,target=/src \
    check-lock /src/environment.yml /src/linux-*.lock \
    && check-lock /src/requirements.in /src/requirements.lock
COPY --from=micromamba /usr/local/bin/micromamba /usr/local/bin/micromamba
COPY linux-*.lock requirements.lock /tmp/
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    --mount=type=bind,from=components,source=trim-python-env,target=/usr/local/bin/trim-python-env \
    micromamba create --yes --root-prefix /tmp/mamba-root --prefix /opt/selkies \
        --file "/tmp/$(target-arch conda).lock" \
    && /opt/selkies/bin/python -m pip install --no-cache-dir --no-deps --require-hashes \
        --no-compile -r /tmp/requirements.lock \
    && /opt/selkies/bin/python -m pip uninstall --yes pip \
    && install -d -m 0755 /out/manifest \
    && /opt/selkies/bin/python -c 'import json, importlib.metadata as m; json.dump({p: m.version(p) for p in ("selkies", "pixelflux", "pcmflux")}, open("/out/manifest/selkies.json", "w"))' \
    && test -x /opt/selkies/bin/selkies \
    && test -f "$(/opt/selkies/bin/python -c 'import selkies, os; print(os.path.dirname(selkies.__file__))')/selkies_web/index.html" \
    && trim-python-env /opt/selkies \
    # conda packages carry group-writable modes; nothing root-owned here should
    # be writable by a group (a user in group 0 could change the desktop).
    && chmod -R go-w /opt/selkies \
    && rm -rf /tmp/mamba-root /opt/selkies/conda-meta/history

# Integration files from rootfs/ (hooks, symlinks, config) at their image paths,
# without group or other write permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R go-w /rootfs

# The desktop: Selkies, its launch scripts, and the /desktop entry for
# jupyter-server-proxy (rootfs/etc/scidesktop/jupyter_server_config.d).
FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /opt/selkies /opt/selkies
COPY --from=build /out/manifest/ /opt/scidesktop/manifest.d/

FROM os AS test
COPY --from=component / /
RUN /opt/selkies/bin/python -c 'import selkies, pixelflux, pcmflux; print("selkies", selkies.__file__)' \
    && /opt/selkies/bin/selkies --help >/dev/null \
    && ldd /opt/selkies/lib/python3*/site-packages/pixelflux/*.so 2>/dev/null | grep 'not found' && exit 1 || true
