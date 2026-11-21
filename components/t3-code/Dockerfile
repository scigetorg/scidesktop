# syntax=docker/dockerfile:1
# T3 Code at /opt/t3-code: the server's release build for the build's
# architecture, and the files that serve it through the notebook server as
# the scigent.ai tile. Not part of the base image; domain images copy it
# (docs/images.md).

# Versions and checksums come from docker-bake.hcl.
ARG UBUNTU_IMAGE

FROM ${UBUNTU_IMAGE} AS build
ARG T3_CODE_VERSION
ARG T3_CODE_SHA256_AMD64
ARG T3_CODE_SHA256_ARM64
ARG TARGETARCH
ARG APT_CACHE_ID
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y curl ca-certificates
# The release archive is the whole server: its web client, its native modules
# and the one library it does not take from the OS. Nothing is compiled and no
# install script runs. The `t3` npm package would download this same archive
# into each home at first use.
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    : "${T3_CODE_VERSION:?}" "${T3_CODE_SHA256_AMD64:?}" "${T3_CODE_SHA256_ARM64:?}" \
    && sha256="T3_CODE_SHA256_${TARGETARCH^^}" \
    && arch="$(target-arch node)" \
    && curl -fsSL --retry 5 --retry-delay 5 --retry-connrefused -o /tmp/t3-code.tar.gz \
        "https://github.com/pingdotgg/t3code/releases/download/v${T3_CODE_VERSION}/t3-${T3_CODE_VERSION}-linux-${arch}.tar.gz" \
    && echo "${!sha256}  /tmp/t3-code.tar.gz" | sha256sum -c - \
    && install -d -m 0755 /opt/t3-code/app /out/opt/scidesktop/manifest.d \
    && tar -xzf /tmp/t3-code.tar.gz -C /opt/t3-code/app --strip-components=1 --no-same-owner \
    && rm /tmp/t3-code.tar.gz \
    && test -f /opt/t3-code/app/client/index.html \
    && test -f "/opt/t3-code/app/node_modules/node-pty/prebuilds/linux-${arch}/pty.node" \
    && find /opt/t3-code/app -type f -name "*.map" -delete \
    && curl -fsSL --retry 5 -o /opt/t3-code/app/LICENSE \
        "https://raw.githubusercontent.com/pingdotgg/t3code/v${T3_CODE_VERSION}/LICENSE" \
    && grep -q "MIT License" /opt/t3-code/app/LICENSE \
    && chmod -R a+rX,go-w /opt/t3-code \
    && test "$(HOME=/tmp/home /opt/t3-code/app/t3 --version)" = "t3 v${T3_CODE_VERSION}" \
    && printf '{"t3-code": "%s"}\n' "${T3_CODE_VERSION}" > /out/opt/scidesktop/manifest.d/t3-code.json

# Integration files from rootfs/ (the proxy entry, the `t3` command link,
# settings defaults) at their image paths, readable and without group or other
# write permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /opt/t3-code/app /opt/t3-code/app
COPY --from=build /out/ /

# T3 Code is served by the notebook server, so the test borrows the Jupyter
# environment: it runs a server with this component's configuration on the
# OS layer and uses T3 through it.
FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,from=jupyter-env,source=/usr/local/etc/jupyter,target=/usr/local/etc/jupyter \
    --mount=type=bind,from=tests,source=t3-code-check.py,target=/tmp/t3-code-check.py \
    --mount=type=bind,source=test.sh,target=/tmp/test.sh \
    bash /tmp/test.sh
