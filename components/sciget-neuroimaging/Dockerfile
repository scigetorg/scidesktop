# syntax=docker/dockerfile:1
# The neuroimaging tools for sciget: the catalog every user of the image gets
# (sciget's system layer, /etc/sciget/catalogs.json), and the module folders
# of its containers on CVMFS (/etc/scidesktop/modulepath.d/60-neurodesk-cvmfs).
# Configuration only; sciget itself is the base's. An image offers the tools
# of the one catalog component it copies: the file has one owner
# (docs/images.md).

ARG UBUNTU_IMAGE

# Integration files from rootfs/ at their image paths, readable and without
# group or other write permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY rootfs/ /rootfs/
# The manifest identifies the catalog list by content, so a change to it
# shows in an image's manifest.
RUN chmod -R a+rX,go-w /rootfs \
    && install -d -m 0755 /rootfs/opt/scidesktop/manifest.d \
    && printf '{"catalog": "neuroimaging", "catalogs_sha256": "%s"}\n' \
        "$(sha256sum /rootfs/etc/sciget/catalogs.json | cut -d ' ' -f 1)" \
        > /rootfs/opt/scidesktop/manifest.d/sciget-neuroimaging.json

FROM scratch AS component
COPY --from=rootfs /rootfs/ /

# On the OS layer with sciget, which must read the file: it ignores nothing
# silently, and a malformed list fails every sciget command.
FROM os AS test
COPY --from=sciget / /
COPY --from=component / /
USER ${NB_UID}
RUN [ "$(sciget catalog list | cut -f 1-3)" = "$(printf 'neuroimaging\t1\tsystem')" ] \
    && [ "$(stat -c '%a %u' /etc/sciget /etc/sciget/catalogs.json)" = "$(printf '755 0\n644 0')" ] \
    && test -x /etc/scidesktop/modulepath.d/60-neurodesk-cvmfs \
    && /etc/scidesktop/modulepath.d/60-neurodesk-cvmfs
