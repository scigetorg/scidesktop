# Scidesktop Selkies desktop adapter: Jupyter + LXQt streamed by Selkies over
# a single port, proxied by jupyter-server-proxy.

# Selkies publishes no 2.x release, so the wheel is built from a pinned commit.
ARG SELKIES_COMMIT=48be9fddcfea0f7342b16108fb46b9c2d41ea112
# Declared here because ARGs used in FROM must precede the first FROM.
ARG BASE_NAME=quay.io/jupyter/base-notebook
ARG BASE_DIGEST=sha256:5bcf92a903b64a32b0d87a103b34e3e9fcab4d1e0c4579be9963966a09f9bbfb

# Ubuntu 24.04 ships Lmod 8.6.19; upstream is 9.3. Built from the release
# tarball so the version is pinned and Renovate-managed. Built in a separate
# stage so the compiler and lua headers never reach the final image.
ARG LMOD_VERSION=9.3
ARG LMOD_SHA256=78e2eedea003d69f11bfab457fd313e9180c55d6960b4d99a826fccb7838ada4

# Stage 1: source
FROM docker.io/library/alpine:3.22 AS selkies-src
ARG SELKIES_COMMIT
RUN apk add --no-cache curl tar \
    && mkdir -p /src \
    && curl -fsSL "https://github.com/selkies-project/selkies/archive/${SELKIES_COMMIT}.tar.gz" \
       | tar -xz --strip-components=1 -C /src

# Stage 2: HTML5 client. Not shipped in the sdist, so pip alone yields a
# server with no web assets; these stages mirror upstream's own build.
FROM docker.io/library/node:26-alpine AS selkies-web
ARG SELKIES_MODE=webrtc
ARG SELKIES_UPLOAD_DIR=/home/jovyan/Desktop
WORKDIR /build
COPY --from=selkies-src /src/addons/selkies-web-core ./selkies-web-core
COPY --from=selkies-src /src/addons/selkies-dashboard ./selkies-dashboard
COPY --from=selkies-src /src/addons/universal-touch-gamepad ./universal-touch-gamepad
COPY --from=selkies-src /src/docs/assets /repo-assets
RUN set -eux; \
    cd selkies-web-core; \
    npm install --no-audit --no-fund; \
    npm run build; \
    cd ../selkies-dashboard; \
    cp ../selkies-web-core/dist/selkies-core.js src/; \
    npm install --no-audit --no-fund; \
    SELKIES_INJECT=1 SELKIES_MODE="${SELKIES_MODE}" SELKIES_UPLOAD_DIR="${SELKIES_UPLOAD_DIR}" npm run build; \
    mkdir -p dist/src; \
    cp ../selkies-web-core/dist/selkies-core.js dist/src/; \
    cp ../universal-touch-gamepad/universalTouchGamepad.js dist/src/; \
    cp -r ../selkies-web-core/dist/jsdb dist/; \
    mkdir -p /webout; \
    cp -ar dist/. /webout/; \
    printf '%s' '{"name":"Selkies","short_name":"Selkies","manifest_version":2,"version":"1.0.0","display":"fullscreen","background_color":"#000000","theme_color":"#000000","icons":[{"src":"icon.png","type":"image/png","sizes":"512x512"}],"start_url":"/"}' > /webout/manifest.json; \
    cp /repo-assets/logo/icon-512x512.png /webout/icon.png; \
    cp /repo-assets/logo/favicon.ico /webout/favicon.ico

# Stage 3: wheel, with the built client bundled into the package
FROM docker.io/library/python:3-slim AS selkies-wheel
ARG SELKIES_COMMIT
RUN python3 -m pip install --no-cache-dir --upgrade build
WORKDIR /opt/pypi
COPY --from=selkies-src /src/src ./src
COPY --from=selkies-src /src/README.md /src/pyproject.toml ./
COPY --from=selkies-web /webout ./src/selkies/selkies_web
RUN sed -i -e "s|^version =.*|version = \"2.0.0.dev0+${SELKIES_COMMIT}\"|g" pyproject.toml \
    && python3 -m build --wheel

# Stage 4: Lmod.
#
# Built on plain Ubuntu rather than the notebook base: conda puts its own
# tclsh and pkg-config ahead of the system ones on PATH, and configure bakes
# whatever it finds into the install. Ubuntu 24.04 matches the base image's
# release, so /usr/bin/lua5.4 resolves identically in the final stage.
FROM docker.io/library/ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea AS lmod-build
ARG LMOD_VERSION
ARG LMOD_SHA256
RUN apt-get update && apt-get install --no-install-recommends -y \
        ca-certificates gcc make curl pkg-config bc \
        lua5.4 liblua5.4-dev lua-posix lua-filesystem tcl tcl-dev \
    && curl -fsSL "https://github.com/TACC/Lmod/archive/refs/tags/${LMOD_VERSION}.tar.gz" -o /tmp/lmod.tar.gz \
    && echo "${LMOD_SHA256}  /tmp/lmod.tar.gz" | sha256sum -c - \
    && mkdir -p /tmp/lmod && tar -xzf /tmp/lmod.tar.gz -C /tmp/lmod --strip-components=1 \
    && cd /tmp/lmod \
    && ./configure --prefix=/opt/apps --with-spiderCacheDir=/var/cache/lmod \
    && make install \
    && rm -rf /tmp/lmod /tmp/lmod.tar.gz

# Stage 5: the image
FROM ${BASE_NAME}@${BASE_DIGEST}

ARG BASE_NAME
ARG BASE_DIGEST
ARG SELKIES_COMMIT

LABEL maintainer="Sciget project <sciget.org>"
LABEL org.scidesktop.status="experimental"
LABEL org.scidesktop.desktop_adapter="selkies"
# The inherited version label is Ubuntu's OS version, passed through
# docker-stacks unchanged; override it and record the base separately.
LABEL org.opencontainers.image.version="selkies-${SELKIES_COMMIT}"
LABEL org.opencontainers.image.base.name="${BASE_NAME}"
LABEL org.opencontainers.image.base.digest="${BASE_DIGEST}"

USER root

# System dependencies: LXQt, X11, audio
RUN apt-get update && apt-get install --no-install-recommends -y \
    # Core
    dbus-x11 dbus-user-session jq curl wget \
    ca-certificates acl ssl-cert sudo \
    # Virtual framebuffer
    xvfb \
    # LXQt desktop (Qt-based, openbox WM)
    lxqt-core qterminal pcmanfm-qt openbox \
    mesa-utils breeze-icon-theme \
    # X11 / input
    x11-utils x11-xkb-utils x11-xserver-utils xserver-xorg-core \
    wmctrl xclip xdotool xsel xcvt \
    libx11-xcb1 libxcb-dri3-0 libxdamage1 libxfixes3 libxv1 libxtst6 \
    libxext6 libxkbcommon0 \
    # GL / EGL
    libdrm2 libegl1 libgl1 libopengl0 libgles2 libglvnd0 libglx0 \
    mesa-va-drivers libva2 vainfo \
    # System python for selkies, deliberately not the conda env
    python3-pip python3-dev python3-setuptools python3-wheel \
    # Audio: selkies captures the PulseAudio monitor source
    libpulse0 pipewire pipewire-alsa pipewire-audio-client-libraries \
    pipewire-pulse wireplumber alsa-utils \
    # Lmod runtime (the build stage has the headers and compiler)
    lua5.4 lua-posix lua-filesystem tcl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Lmod: `module` is the single access path for containerised applications.
COPY --from=lmod-build /opt/apps /opt/apps
RUN ln -s /opt/apps/lmod/lmod/init/profile /etc/profile.d/z00_lmod.sh \
    && ln -s /opt/apps/lmod/lmod/init/cshrc /etc/profile.d/z00_lmod.csh \
    && /opt/apps/lmod/lmod/libexec/lmod --version

# pixelflux/pcmflux resolve from PyPI as manylinux wheels.
COPY --from=selkies-wheel /opt/pypi/dist/*.whl /tmp/
RUN PIP_BREAK_SYSTEM_PACKAGES=1 /usr/bin/pip3 install --no-cache-dir /tmp/*.whl \
    && rm -f /tmp/*.whl \
    && command -v selkies >/dev/null \
    && command -v selkies-resize >/dev/null \
    && test -f /usr/local/lib/python3*/dist-packages/selkies/selkies_web/index.html \
    || { echo "ERROR: selkies or its web client did not install"; exit 1; }

USER ${NB_USER}

RUN /opt/conda/bin/pip install --no-cache-dir 'jupyter-server-proxy==4.4.0'

RUN jupyter server extension disable \
        nbclassic notebook_shim \
    && jupyter labextension disable \
        '@jupyterlab/apputils-extension:announcements' \
        '@jupyterlab/extensionmanager-extension:plugin' \
        '@jupyterlab/help-extension:about' \
    || true

USER root

RUN mkdir -p /opt/scidesktop /etc/jupyter

COPY --chown=root:users config/selkies/start_desktop.sh /opt/scidesktop/start_desktop.sh
COPY --chown=root:users config/selkies/start_selkies.sh /opt/scidesktop/start_selkies.sh
RUN chmod +rx /opt/scidesktop/*.sh

# Replaces the upstream conda hook with a static equivalent; see the file.
COPY --chown=root:users config/selkies/10activate-conda-env.sh \
     /usr/local/bin/before-notebook.d/10activate-conda-env.sh
RUN chmod +rx /usr/local/bin/before-notebook.d/*

# Same substitution for interactive shells; conda.sh defines the same
# function without spawning python.
RUN sed -i 's|eval "$(conda shell.bash hook)"|. /opt/conda/etc/profile.d/conda.sh|' \
        "/home/${NB_USER}/.bashrc" \
    && grep -q 'profile.d/conda.sh' "/home/${NB_USER}/.bashrc"

COPY config/selkies/pcmanfm-qt-settings.conf /etc/xdg/pcmanfm-qt/lxqt/settings.conf
RUN chmod +r /etc/xdg/pcmanfm-qt/lxqt/settings.conf

COPY config/selkies/jupyter_notebook_config.py /etc/jupyter/jupyter_notebook_config.py
RUN chmod +r /etc/jupyter/jupyter_notebook_config.py

RUN printf '%s\n' \
    'c.LabApp.check_for_updates_class = "jupyterlab.handlers.announcements.NeverCheckForUpdate"' \
    >> /etc/jupyter/jupyter_server_config.py

ENV DISPLAY=:20
ENV JUPYTER_DISABLE_RESOURCE_USAGE=1

# No ENTRYPOINT/CMD override: start.sh handles the spawner's command, NB_UID
# remap, /etc/passwd for arbitrary UIDs and CHOWN_HOME.
# The desktop is not started here; start_selkies.sh starts it on first use.

WORKDIR "/home/${NB_USER}"
USER ${NB_UID}
