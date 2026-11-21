# syntax=docker/dockerfile:1
# code-server (VS Code in the browser) at /opt/code-server, opened from the
# VS Code launcher tile. It is the upstream release for the build's
# architecture, unmodified and checked against the checksum in
# docker-bake.hcl. Not part of the base image; domain images copy it
# (docs/images.md).

# Versions and checksums come from docker-bake.hcl.
ARG UBUNTU_IMAGE

FROM ${UBUNTU_IMAGE} AS build
ARG TARGETARCH
ARG APT_CACHE_ID
ARG CODE_SERVER_VERSION
ARG CODE_SERVER_SHA256_AMD64
ARG CODE_SERVER_SHA256_ARM64
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y curl ca-certificates
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    --mount=type=bind,from=components,source=fetch,target=/usr/local/bin/fetch \
    : "${CODE_SERVER_VERSION:?}" "${CODE_SERVER_SHA256_AMD64:?}" "${CODE_SERVER_SHA256_ARM64:?}" \
    && sha256="CODE_SERVER_SHA256_${TARGETARCH^^}" \
    && release="code-server-${CODE_SERVER_VERSION}-linux-$(target-arch deb)" \
    && fetch "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/${release}.tar.gz" \
        "${!sha256}" /tmp/code-server.tar.gz \
    && mkdir -p /opt/code-server \
    && tar -xzf /tmp/code-server.tar.gz -C /opt/code-server --strip-components=1 --no-same-owner \
    && rm /tmp/code-server.tar.gz \
    # Source maps are for debugging code-server itself.
    && find /opt/code-server -type f \( -name '*.js.map' -o -name '*.css.map' \) -delete \
    && chmod -R a+rX,go-w /opt/code-server \
    && /opt/code-server/bin/code-server --version | grep -F "${CODE_SERVER_VERSION}" \
    && test -s /opt/code-server/LICENSE \
    && test -s /opt/code-server/ThirdPartyNotices.txt \
    # The folder code-server reads as its system extensions: a link to each
    # extension of the release, and whatever extensions other components put
    # beside them (install-extension). Every user gets them; none is copied
    # into a home.
    && install -d -m 0755 /out/usr/local/share/code-server/extensions \
    && for bundled in /opt/code-server/lib/vscode/extensions/*; do \
        ln -s "${bundled}" "/out/usr/local/share/code-server/extensions/$(basename "${bundled}")"; \
    done \
    && test -L /out/usr/local/share/code-server/extensions/git \
    && install -d -m 0755 /out/manifest \
    && printf '{"code-server": "%s", "vscode": "%s"}\n' "${CODE_SERVER_VERSION}" \
        "$(sed -n 's/^ *"version": "\(.*\)",$/\1/p' /opt/code-server/lib/vscode/package.json | head -n 1)" \
        > /out/manifest/code-server.json \
    && cat /out/manifest/code-server.json

# Integration files from rootfs/ (the command link, the launcher tile, home
# defaults) at their image paths, readable and without group or other write
# permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /opt/code-server /opt/code-server
COPY --from=build /out/manifest/ /opt/scidesktop/manifest.d/
COPY --from=build /out/usr/ /usr/

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,source=test.sh,target=/tmp/test.sh bash /tmp/test.sh
