# syntax=docker/dockerfile:1
# T3 Connect for images with T3 Code, at /opt/t3-connect: remote access to
# the session's T3 Code from the T3 desktop and mobile apps, through T3's
# relay. It is the relay client T3 uses (cloudflared, Apache-2.0: the
# upstream release, checked against the checksum in docker-bake.hcl) and a
# page behind the notebook server's login that runs T3's device
# authorization. Off until the user sets it up there; nothing listens beyond
# loopback. It reaches T3 Code through that component's extension points
# only. Not part of the base image (docs/t3-connect.md).

# Versions and checksums come from docker-bake.hcl.
ARG UBUNTU_IMAGE

FROM ${UBUNTU_IMAGE} AS build
ARG T3_CLOUDFLARED_VERSION
ARG T3_CLOUDFLARED_SHA256_AMD64
ARG T3_CLOUDFLARED_SHA256_ARM64
ARG TARGETARCH
ARG APT_CACHE_ID
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=private \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=private \
    apt-get update && apt-get install --no-install-recommends -y curl ca-certificates
# One static executable per architecture. T3 would otherwise download its own
# copy into each home when a user sets Connect up.
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    --mount=type=bind,from=components,source=fetch,target=/usr/local/bin/fetch \
    : "${T3_CLOUDFLARED_VERSION:?}" "${T3_CLOUDFLARED_SHA256_AMD64:?}" "${T3_CLOUDFLARED_SHA256_ARM64:?}" \
    && sha256="T3_CLOUDFLARED_SHA256_${TARGETARCH^^}" \
    && release="https://github.com/cloudflare/cloudflared/releases/download/${T3_CLOUDFLARED_VERSION}" \
    && install -d -m 0755 /out/opt/t3-connect/bin /out/opt/scidesktop/manifest.d \
    && fetch "${release}/cloudflared-linux-$(target-arch deb)" \
        "${!sha256}" /out/opt/t3-connect/bin/cloudflared \
    && chmod 0755 /out/opt/t3-connect/bin/cloudflared \
    && /out/opt/t3-connect/bin/cloudflared --version | grep -F "version ${T3_CLOUDFLARED_VERSION} " \
    && curl -fsSL --retry 5 -o /out/opt/t3-connect/LICENSE-cloudflared \
        "https://raw.githubusercontent.com/cloudflare/cloudflared/${T3_CLOUDFLARED_VERSION}/LICENSE" \
    && grep -q "Apache License" /out/opt/t3-connect/LICENSE-cloudflared \
    && printf '{"cloudflared": "%s"}\n' "${T3_CLOUDFLARED_VERSION}" > /out/opt/scidesktop/manifest.d/t3-connect.json

# Integration files from rootfs/ (the page and its server extension, the
# files that tell T3 Code about the relay client and the page) at their image
# paths, readable and without group or other write permission whatever the
# checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /out/ /

# On the OS layer with T3 Code, through a notebook server with both
# components' configuration (the Jupyter environment is borrowed).
FROM os AS test
COPY --from=t3-code / /
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,from=jupyter-env,source=/usr/local/etc/jupyter,target=/usr/local/etc/jupyter \
    --mount=type=bind,from=tests,source=t3-connect-check.py,target=/tmp/t3-connect-check.py \
    --mount=type=bind,source=test.sh,target=/tmp/test.sh \
    bash /tmp/test.sh
