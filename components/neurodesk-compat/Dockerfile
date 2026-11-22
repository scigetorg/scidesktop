# syntax=docker/dockerfile:1
# Neurodesk neuroimaging compatibility layer:
#   - FreeSurfer APPTAINERENV_SUBJECTS_DIR and NF_NEURO_MODULES_DIR defaults
#   - Legacy /neurodesktop-storage/containers/modules discovery (55-neurodesk-local)
#   - Pinned nf-neuro Nextflow modules at /opt/nf-neuro/modules
#   - Getting Started notebook seeded into new homes

ARG UBUNTU_IMAGE
FROM ${UBUNTU_IMAGE} AS build
ARG NF_NEURO_MODULES_COMMIT
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY --from=nf-neuro-src . /tmp/nf-neuro
RUN : "${NF_NEURO_MODULES_COMMIT:?}" \
    && install -d -m 0755 /out/opt/nf-neuro/modules /out/opt/scidesktop/manifest.d \
    && cp -a /tmp/nf-neuro/. /out/opt/nf-neuro/modules/ \
    && rm -rf /out/opt/nf-neuro/modules/.git \
    && printf '{"nf-neuro-modules": "%s"}\n' "${NF_NEURO_MODULES_COMMIT}" \
        > /out/opt/scidesktop/manifest.d/neurodesk-compat.json \
    && chmod -R a+rX,go-w /out

FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN bash -euo pipefail -c '. /etc/profile.d/neurodesk-compat.sh \
    && [ "${NF_NEURO_MODULES_DIR}" = "/opt/nf-neuro/modules" ] \
    && [ "${APPTAINERENV_SUBJECTS_DIR}" = "${HOME}/freesurfer-subjects-dir" ] \
    && test -d /opt/nf-neuro/modules/modules \
    && test -r /etc/scidesktop/home-defaults/getting-started.ipynb \
    && test -x /etc/scidesktop/modulepath.d/55-neurodesk-local \
    && tmp="$(mktemp -d)" \
    && mkdir -p "${tmp}/modules" \
    && [ "$(NEURODESKTOP_LOCAL_CONTAINERS="${tmp}" /etc/scidesktop/modulepath.d/55-neurodesk-local)" = "${tmp}/modules" ] \
    && rm -rf "${tmp}" \
    && test -r /opt/scidesktop/manifest.d/neurodesk-compat.json'
