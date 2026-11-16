# syntax=docker/dockerfile:1
# sciget, built from a local checkout passed as the named context
# `sciget-src`. Replaced by a COPY from the published sciget image once it
# exists.

# Versions come from docker-bake.hcl.
ARG SCIGET_GO_VERSION
ARG UBUNTU_IMAGE
FROM docker.io/library/golang:${SCIGET_GO_VERSION}-bookworm AS build
ARG NB_UID
ARG NB_GID
COPY --from=sciget-src . /src
WORKDIR /src
RUN --mount=type=cache,target=/root/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o /out/sciget . \
    && /out/sciget --version \
    && install -d -m 0755 /out/manifest \
    && printf '{"sciget": "%s"}\n' "$(/out/sciget --version | awk '{print $NF}')" > /out/manifest/sciget.json \
    # Launchers sciget writes for the desktop menu (XDG_DATA_DIRS).
    && install -d -m 0755 -o "${NB_UID:?}" -g "${NB_GID:?}" /out/opt/sciget /out/opt/sciget/applications

# Integration files from rootfs/ (hooks, symlinks, config) at their image paths,
# without group or other write permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R go-w /rootfs

# sciget, its default catalogue (/etc/sciget) and the hook that copies it to
# each user on first start (30-sciget).
FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /out/sciget /usr/local/bin/sciget
COPY --from=build /out/opt/ /opt/
COPY --from=build /out/manifest/ /opt/scidesktop/manifest.d/

FROM os AS test
COPY --from=component / /
RUN sciget --version \
    && test -x /usr/local/bin/before-notebook.d/30-sciget \
    && python3 -c 'import json; json.load(open("/etc/sciget/catalogues.json")); json.load(open("/etc/sciget/config.json"))' \
    && test "$(stat -c %u /opt/sciget/applications)" = "${NB_UID}"
