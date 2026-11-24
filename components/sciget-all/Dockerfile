# syntax=docker/dockerfile:1
# All sciget domain catalogs (neuroimaging, microscopy, datascience and
# dermatology) for the scidesktop base image (/etc/sciget/catalogs.json), plus
# the CVMFS module folders (/etc/scidesktop/modulepath.d/60-neurodesk-cvmfs).
# Domain images that want a single domain override /etc/sciget/catalogs.json by
# copying sciget-<domain>.

ARG UBUNTU_IMAGE

FROM ${UBUNTU_IMAGE} AS rootfs
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs \
    && install -d -m 0755 /rootfs/opt/scidesktop/manifest.d \
    && printf '{"catalogs": ["neuroimaging", "microscopy", "datascience", "dermatology"], "catalogs_sha256": "%s"}\n' \
        "$(sha256sum /rootfs/etc/sciget/catalogs.json | cut -d ' ' -f 1)" \
        > /rootfs/opt/scidesktop/manifest.d/sciget-all.json

FROM scratch AS component
COPY --from=rootfs /rootfs/ /

FROM os AS test
COPY --from=sciget / /
COPY --from=component / /
USER ${NB_UID}
RUN [ "$(sciget catalog list | cut -f 1-3)" = "$(printf 'neuroimaging\t1\tsystem\nmicroscopy\t2\tsystem\ndatascience\t3\tsystem\ndermatology\t4\tsystem')" ] \
    && [ "$(stat -c '%a %u' /etc/sciget /etc/sciget/catalogs.json)" = "$(printf '755 0\n644 0')" ] \
    && paths="$(/etc/scidesktop/modulepath.d/50-sciget)" \
    && grep -q '/neuroimaging$' <<<"${paths}" \
    && grep -q '/microscopy$' <<<"${paths}" \
    && grep -q '/datascience$' <<<"${paths}" \
    && grep -q '/dermatology$' <<<"${paths}" \
    && test -x /etc/scidesktop/modulepath.d/60-neurodesk-cvmfs \
    && [ -z "$(SCIDESKTOP_CVMFS_MODE=disabled /etc/scidesktop/modulepath.d/60-neurodesk-cvmfs)" ] \
    && /etc/scidesktop/modulepath.d/60-neurodesk-cvmfs
