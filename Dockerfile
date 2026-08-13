# Jupyter, LXQt desktop, streamed by Selkies

# Selkies
ARG SELKIES_COMMIT=48be9fddcfea0f7342b16108fb46b9c2d41ea112
# Declared here because ARGs used in FROM must precede the first FROM.
ARG BASE_NAME=quay.io/jupyter/base-notebook
ARG BASE_DIGEST=sha256:5bcf92a903b64a32b0d87a103b34e3e9fcab4d1e0c4579be9963966a09f9bbfb

# Lmod
ARG LMOD_VERSION=9.3
ARG LMOD_SHA256=78e2eedea003d69f11bfab457fd313e9180c55d6960b4d99a826fccb7838ada4

# Apptainer
ARG APPTAINER_VERSION=1.5.3
ARG APPTAINER_GO_VERSION=1.26.5
ARG APPTAINER_GRPC_VERSION=1.83.0

# Stage 0: Apptainer
FROM docker.io/library/golang:${APPTAINER_GO_VERSION}-bookworm AS apptainer
ARG APPTAINER_VERSION
ARG APPTAINER_GRPC_VERSION
RUN echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries
RUN apt-get update && apt-get install --no-install-recommends -y \
        autoconf automake build-essential ca-certificates cryptsetup curl \
        fakeroot git libattr1-dev libfuse3-dev liblzo2-dev liblz4-dev \
        liblzma-dev libprotobuf-c-dev libseccomp-dev libsubid-dev \
        libtalloc-dev libtool libzstd-dev pkg-config uidmap zlib1g-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    git clone --depth 1 --branch "v${APPTAINER_VERSION}" \
        https://github.com/apptainer/apptainer.git /tmp/apptainer \
    && cd /tmp/apptainer \
    && go get "google.golang.org/grpc@v${APPTAINER_GRPC_VERSION}" \
    && go mod tidy && go mod download \
    && ./scripts/download-dependencies \
    && ./scripts/compile-dependencies \
    && printf '%s\n' "${APPTAINER_VERSION}" > VERSION \
    && ./mconfig --prefix=/opt/apptainer --with-suid \
    && make -C builddir \
    && make -C builddir install \
    && ./scripts/install-dependencies \
    && /opt/apptainer/bin/apptainer --version \
    && rm -rf /tmp/apptainer

# Stage 1: source
FROM docker.io/library/alpine:3.22@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce AS selkies-src
ARG SELKIES_COMMIT
RUN apk add --no-cache curl tar \
    && mkdir -p /src \
    && curl -fsSL --retry 5 --retry-delay 5 --retry-connrefused "https://github.com/selkies-project/selkies/archive/${SELKIES_COMMIT}.tar.gz" \
       | tar -xz --strip-components=1 -C /src

# Stage 2: HTML5 client, not shipped in the sdist
FROM docker.io/library/node:26-alpine@sha256:aadf416b2cdce311a8811ba3f0608a61b77dbf997500e2eafe781b51f6a0b019 AS selkies-web
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
FROM docker.io/library/python:3-slim@sha256:a7fb1e634c4a578f9e0bd6327f11a3cde11b7a9395f48e24360c0988bcc5c2bc AS selkies-wheel
ARG SELKIES_COMMIT
RUN python3 -m pip install --no-cache-dir --upgrade build
WORKDIR /opt/pypi
COPY --from=selkies-src /src/src ./src
COPY --from=selkies-src /src/README.md /src/pyproject.toml ./
COPY --from=selkies-web /webout ./src/selkies/selkies_web
RUN sed -i -e "s|^version =.*|version = \"2.0.0.dev0+${SELKIES_COMMIT}\"|g" pyproject.toml \
    && python3 -m build --wheel

# Stage 4: Lmod. Plain Ubuntu; conda's tclsh and pkg-config shadow the
# system ones on PATH.
FROM docker.io/library/ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea AS lmod-build
ARG LMOD_VERSION
ARG LMOD_SHA256
RUN echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries
RUN apt-get update && apt-get install --no-install-recommends -y \
        ca-certificates gcc make curl pkg-config bc \
        lua5.4 liblua5.4-dev lua-posix lua-filesystem tcl tcl-dev \
    && curl -fsSL --retry 5 --retry-delay 5 --retry-connrefused "https://github.com/TACC/Lmod/archive/refs/tags/${LMOD_VERSION}.tar.gz" -o /tmp/lmod.tar.gz \
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
LABEL org.opencontainers.image.version="selkies-${SELKIES_COMMIT}"
LABEL org.opencontainers.image.base.name="${BASE_NAME}"
LABEL org.opencontainers.image.base.digest="${BASE_DIGEST}"

USER root

# Build against an archive snapshot
ARG APT_SNAPSHOT=20260801T000000Z
RUN echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries
RUN cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.live \
    && sed -i -E "s|^URIs: https?://((archive\|security)\.ubuntu\.com/ubuntu\|ports\.ubuntu\.com/ubuntu-ports)/?|URIs: https://snapshot.ubuntu.com/ubuntu/${APT_SNAPSHOT}|" \
        /etc/apt/sources.list.d/ubuntu.sources \
    && grep -q "snapshot.ubuntu.com" /etc/apt/sources.list.d/ubuntu.sources

# System dependencies: LXQt, X11, audio
RUN apt-get update && apt-get install --no-install-recommends -y \
    # Core
    dbus-x11 dbus-user-session curl wget \
    ca-certificates acl sudo \
    # Virtual framebuffer
    xvfb \
    # LXQt desktop
    lxqt-core qterminal pcmanfm-qt openbox breeze-icon-theme \
    # X11 / input
    x11-utils x11-xkb-utils x11-xserver-utils xcvt \
    libx11-xcb1 libxcb-dri3-0 libxdamage1 libxfixes3 libxv1 libxtst6 \
    libxext6 libxkbcommon0 \
    # GL / EGL
    libdrm2 libegl1 libgl1 libopengl0 libgles2 libglvnd0 libglx0 \
    # System python for selkies, not the conda env
    python3-pip \
    # Audio
    libpulse0 pipewire pipewire-alsa pipewire-audio-client-libraries \
    pipewire-pulse wireplumber alsa-utils \
    # Lmod runtime
    lua5.4 lua-posix lua-filesystem tcl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Lmod
COPY --from=lmod-build /opt/apps /opt/apps
RUN ln -s /opt/apps/lmod/lmod/init/profile /etc/profile.d/z00_lmod.sh \
    && ln -s /opt/apps/lmod/lmod/init/cshrc /etc/profile.d/z00_lmod.csh \
    && /opt/apps/lmod/lmod/libexec/lmod --version

# Apptainer. setuid disabled; libtalloc2/libprotobuf-c1 are proot's libs.
COPY --from=apptainer /opt/apptainer /opt/apptainer
RUN ln -sf /opt/apptainer/bin/apptainer /usr/local/bin/apptainer \
    && ln -sf /opt/apptainer/bin/singularity /usr/local/bin/singularity \
    && rm -rf /opt/apptainer/libexec/apptainer/cni \
    && sed -i 's/^allow setuid = yes/allow setuid = no/' /opt/apptainer/etc/apptainer/apptainer.conf \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
        fuse-overlayfs squashfuse libtalloc2 libprotobuf-c1 uidmap fakeroot \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && apptainer --version

# CVMFS
ARG CVMFS_VERSION=2.13.3
ARG CVMFS_CONFIG_VERSION=1.1-0
RUN cd /tmp \
    && arch="$(dpkg --print-architecture)" \
    && for p in cvmfs cvmfs-libs cvmfs-fuse3; do \
         curl -fsSL --retry 5 --retry-delay 5 --retry-connrefused -O "https://ecsft.cern.ch/dist/cvmfs/cvmfs-${CVMFS_VERSION}/${p}_${CVMFS_VERSION}+ubuntu24.04_${arch}.deb"; \
       done \
    && curl -fsSL --retry 5 --retry-delay 5 --retry-connrefused -O "https://ecsft.cern.ch/dist/cvmfs/cvmfs-config/cvmfs-config-none_${CVMFS_CONFIG_VERSION}_all.deb" \
    && apt-get update \
    && apt-get install --no-install-recommends -y ./cvmfs*.deb \
    && rm -f /tmp/*.deb \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && cvmfs2 --version

# Selkies
COPY --from=selkies-wheel /opt/pypi/dist/*.whl /tmp/
COPY config/selkies/constraints.txt /tmp/constraints.txt
RUN PIP_BREAK_SYSTEM_PACKAGES=1 /usr/bin/pip3 install --no-cache-dir -c /tmp/constraints.txt /tmp/*.whl \
    && rm -f /tmp/*.whl /tmp/constraints.txt \
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

# Replaces the upstream conda activation hook.
COPY --chown=root:users config/selkies/10activate-conda-env.sh \
     /usr/local/bin/before-notebook.d/10activate-conda-env.sh
RUN chmod +rx /usr/local/bin/before-notebook.d/*

# Same for interactive shells.
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

# Restore live sources for runtime apt.
RUN mv /etc/apt/sources.list.d/ubuntu.sources.live /etc/apt/sources.list.d/ubuntu.sources

ENV DISPLAY=:20
ENV JUPYTER_DISABLE_RESOURCE_USAGE=1

# No ENTRYPOINT/CMD override; start.sh handles the spawner's command and
# NB_UID remap. The desktop starts on first use.

WORKDIR "/home/${NB_USER}"
USER ${NB_UID}
