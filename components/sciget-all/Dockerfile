# syntax=docker/dockerfile:1
# All sciget domain catalogs (neuroimaging, microscopy, datascience,
# dermatology, preclinical, molecular-imaging and genomics) for the scidesktop
# base image (/etc/sciget/catalogs.json), plus the CVMFS module folders
# (/etc/scidesktop/modulepath.d/60-neurodesk-cvmfs). Domain images that want a
# single domain override /etc/sciget/catalogs.json by copying sciget-<domain>.

ARG UBUNTU_IMAGE

FROM ${UBUNTU_IMAGE} AS rootfs
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs \
    && install -d -m 0755 /rootfs/opt/scidesktop/manifest.d \
    && printf '{"catalogs": ["neuroimaging", "microscopy", "datascience", "dermatology", "preclinical", "molecular-imaging", "genomics"], "catalogs_sha256": "%s"}\n' \
        "$(sha256sum /rootfs/etc/sciget/catalogs.json | cut -d ' ' -f 1)" \
        > /rootfs/opt/scidesktop/manifest.d/sciget-all.json

FROM scratch AS component
COPY --from=rootfs /rootfs/ /

FROM os AS test
ARG TARGETARCH
COPY --from=sciget / /
COPY --from=component / /
USER ${NB_UID}
RUN [ "$(sciget catalog list | cut -f 1-3)" = "$(printf 'neuroimaging\t1\tsystem\nmicroscopy\t2\tsystem\ndatascience\t3\tsystem\ndermatology\t4\tsystem\npreclinical\t5\tsystem\nmolecular-imaging\t6\tsystem\ngenomics\t7\tsystem')" ] \
    && [ "$(stat -c '%a %u' /etc/sciget /etc/sciget/catalogs.json)" = "$(printf '755 0\n644 0')" ] \
    && paths="$(/etc/scidesktop/modulepath.d/50-sciget)" \
    && grep -q '/neuroimaging$' <<<"${paths}" \
    && grep -q '/microscopy$' <<<"${paths}" \
    && grep -q '/datascience$' <<<"${paths}" \
    && grep -q '/dermatology$' <<<"${paths}" \
    && grep -q '/preclinical$' <<<"${paths}" \
    && grep -q '/molecular-imaging$' <<<"${paths}" \
    && grep -q '/genomics$' <<<"${paths}" \
    && test -x /etc/scidesktop/modulepath.d/60-neurodesk-cvmfs \
    && test -x /opt/scidesktop/cvmfs-domain-modules \
    && [ -z "$(SCIDESKTOP_CVMFS_MODE=disabled /etc/scidesktop/modulepath.d/60-neurodesk-cvmfs)" ] \
    && /etc/scidesktop/modulepath.d/60-neurodesk-cvmfs \
    # Narrowed non-neuroimaging catalog exposes only catalog-listed CVMFS modules, never neurodesk-modules/*,
    # respects use:false, exact source hash, explicit architecture, key-derived image, and stale-cache cleanup.
    && work="$(mktemp -d)" \
    && url="https://example.invalid/domains.json" \
    && cat_hash="$(printf '%s\n%s' "${url}" "microscopy" | sha256sum | cut -c1-12)" \
    && mkdir -p "${work}/cvmfs/neurodesk-modules/functional_imaging/afni" \
        "${work}/cvmfs/containers/modules/afni" \
        "${work}/cvmfs/containers/modules/cellpose" \
        "${work}/cvmfs/containers/modules/armtool" \
        "${work}/cvmfs/containers/modules/x86tool" \
        "${work}/cvmfs/containers/modules/keytool" \
        "${work}/cache/sciget/catalogs/microscopy-${cat_hash}" \
        "${work}/cache/sciget/catalogs/microscopy-other-deadbeef1234" \
    && printf 'whatis("afni")\n' > "${work}/cvmfs/neurodesk-modules/functional_imaging/afni/26.0.lua" \
    && printf 'whatis("afni")\n' > "${work}/cvmfs/containers/modules/afni/26.0.lua" \
    && printf 'whatis("cellpose")\n' > "${work}/cvmfs/containers/modules/cellpose/4.2.1.1.lua" \
    && printf 'whatis("armtool")\n' > "${work}/cvmfs/containers/modules/armtool/1.0.lua" \
    && printf 'whatis("x86tool")\n' > "${work}/cvmfs/containers/modules/x86tool/1.0.lua" \
    && printf 'whatis("keytool")\n' > "${work}/cvmfs/containers/modules/keytool/2.0" \
    && printf '[{"name":"microscopy","url":"%s","domain":"microscopy","use":true,"dir":"%s/cvmfs/containers"},{"name":"disabledcat","url":"%s","domain":"disabled","use":false,"dir":"%s/cvmfs/containers"}]\n' "${url}" "${work}" "${url}" "${work}" > "${work}/catalogs.json" \
    && printf '{"cellpose":{"apps":{"cellpose 4.2.1.1":{"image":"cellpose_4.2.1.1"}}},"armtool":{"apps":{"armtool 1.0":{"image":"armtool_1.0","architecture":"aarch64"},"armtoolGUI 1.0":{"image":"armtool_1.0"}}},"x86tool":{"apps":{"x86tool 1.0":{"image":"x86tool_1.0","architecture":"linux/amd64"}}},"keytool":{"apps":{"keytool 2.0":{"version":"20260101"}}}}\n' > "${work}/cache/sciget/catalogs/microscopy-${cat_hash}/apps.json" \
    && printf '{"afni":{"apps":{"afni 26.0":{"image":"afni_26.0"}}}}\n' > "${work}/cache/sciget/catalogs/microscopy-other-deadbeef1234/apps.json" \
    && mkdir -p "${work}/custom-cfg" "${work}/custom-cache/catalogs/microscopy-${cat_hash}" \
    && printf '{"cache_dir":"%s/custom-cache"}\n' "${work}" > "${work}/custom-cfg/config.json" \
    && cp "${work}/cache/sciget/catalogs/microscopy-${cat_hash}/apps.json" "${work}/custom-cache/catalogs/microscopy-${cat_hash}/apps.json" \
    && filtered="$(SCIGET_SYSTEM_CATALOGS="${work}/catalogs.json" NEURODESK_CVMFS_ROOT="${work}/cvmfs" XDG_CACHE_HOME="${work}/cache" XDG_CONFIG_HOME="${work}/cfg" /etc/scidesktop/modulepath.d/60-neurodesk-cvmfs)" \
    && [ "$(printf '%s\n' "${filtered}" | wc -l)" -eq 1 ] \
    && [[ "${filtered}" == "${work}/cache/sciget/cvmfs-modules/"*"/microscopy-${cat_hash}" ]] \
    && ! test -e "${filtered}/afni" \
    && test -L "${filtered}/cellpose/4.2.1.1.lua" \
    && test -L "${filtered}/keytool/2.0" \
    && case "${TARGETARCH}" in \
         arm64) test -L "${filtered}/armtool/1.0.lua" && ! test -e "${filtered}/x86tool" ;; \
         *) test -L "${filtered}/x86tool/1.0.lua" && ! test -e "${filtered}/armtool" ;; \
       esac \
    && custom_filtered="$(SCIGET_SYSTEM_CATALOGS="${work}/catalogs.json" SCIGET_CONFIG="${work}/custom-cfg/config.json" NEURODESK_CVMFS_ROOT="${work}/cvmfs" XDG_CACHE_HOME="${work}/empty-cache" /etc/scidesktop/modulepath.d/60-neurodesk-cvmfs)" \
    && [[ "${custom_filtered}" == "${work}/custom-cache/cvmfs-modules/"*"/microscopy-${cat_hash}" ]] \
    && test -L "${custom_filtered}/cellpose/4.2.1.1.lua" \
    && rm -f "${work}/cache/sciget/catalogs/microscopy-${cat_hash}/apps.json" \
    && SCIGET_SYSTEM_CATALOGS="${work}/catalogs.json" NEURODESK_CVMFS_ROOT="${work}/cvmfs" XDG_CACHE_HOME="${work}/cache" XDG_CONFIG_HOME="${work}/cfg" /opt/scidesktop/cvmfs-domain-modules --sync \
    && ! test -e "${filtered}/cellpose" \
    && rm -rf "${work}"
