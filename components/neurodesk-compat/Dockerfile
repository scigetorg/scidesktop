# syntax=docker/dockerfile:1
# Neurodesk neuroimaging compatibility layer:
#   - FreeSurfer APPTAINERENV_SUBJECTS_DIR and NF_NEURO_MODULES_DIR defaults
#   - Legacy /neurodesktop-storage/containers/modules discovery (55-neurodesk-local)
#   - Pinned nf-neuro Nextflow modules at /opt/nf-neuro/modules (with local git metadata)
#   - Getting Started notebook seeded into new homes

ARG UBUNTU_IMAGE
FROM ${UBUNTU_IMAGE} AS build
ARG NF_NEURO_MODULES_COMMIT
ARG TARGETARCH
ARG APT_CACHE_ID
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=private \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=private \
    apt-get update && apt-get install --no-install-recommends -y git
COPY --from=nf-neuro-src . /tmp/nf-neuro
RUN : "${NF_NEURO_MODULES_COMMIT:?}" \
    && install -d -m 0755 /out/opt/nf-neuro/modules /out/opt/scidesktop/manifest.d \
    && cp -a /tmp/nf-neuro/. /out/opt/nf-neuro/modules/ \
    && rm -rf /out/opt/nf-neuro/modules/.git \
    # BuildKit strips .git from git contexts; initialize a deterministic
    # single-commit local repository so `nf-core modules --git-remote` works offline.
    && git -C /out/opt/nf-neuro/modules init -q -b main \
    && git -C /out/opt/nf-neuro/modules config user.name "scidesktop" \
    && git -C /out/opt/nf-neuro/modules config user.email "scidesktop@sciget.org" \
    && git -C /out/opt/nf-neuro/modules add -A \
    && GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" \
        git -C /out/opt/nf-neuro/modules commit -q -m "nf-neuro/modules@${NF_NEURO_MODULES_COMMIT}" \
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
    && git -c safe.directory=/opt/nf-neuro/modules -C /opt/nf-neuro/modules rev-parse --is-inside-work-tree | grep -qx true \
    && test -r /etc/scidesktop/home-defaults/getting-started.ipynb \
    && test -x /etc/scidesktop/modulepath.d/55-neurodesk-local \
    && tmp="$(mktemp -d)" \
    && mkdir -p "${tmp}/modules" \
    && [ "$(NEURODESKTOP_LOCAL_CONTAINERS="${tmp}" /etc/scidesktop/modulepath.d/55-neurodesk-local)" = "${tmp}/modules" ] \
    && rm -rf "${tmp}" \
    && test -r /opt/scidesktop/manifest.d/neurodesk-compat.json'
