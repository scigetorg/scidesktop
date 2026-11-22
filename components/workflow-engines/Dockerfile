# syntax=docker/dockerfile:1
# Generic scientific workflow engines at /opt/workflow-engines, shared across
# all desktops (scidesktop, microdesktop, aidesktop, neurodesktop):
#   - Nextflow (Apache-2.0): offline fat distribution executable
#   - nf-test (MIT): test runner JAR for Nextflow pipelines
#   - Snakemake (MIT): isolated locked Python environment

ARG UBUNTU_IMAGE
FROM ${UBUNTU_IMAGE} AS build
ARG TARGETARCH
ARG APT_CACHE_ID
ARG NEXTFLOW_VERSION
ARG NEXTFLOW_SHA256
ARG NF_TEST_VERSION
ARG NF_TEST_SHA256
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y ca-certificates curl
RUN --mount=type=bind,from=components,source=check-lock,target=/usr/local/bin/check-lock \
    --mount=type=bind,source=.,target=/src \
    check-lock /src/environment.yml /src/linux-*.lock \
    && check-lock /src/requirements.in /src/requirements.lock
COPY --from=micromamba /usr/local/bin/micromamba /usr/local/bin/micromamba
COPY linux-*.lock requirements.lock /tmp/
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    --mount=type=bind,from=components,source=fetch,target=/usr/local/bin/fetch \
    install -d -m 0755 /opt/workflow-engines/bin /opt/workflow-engines/nf-test \
        /out/usr/local/bin /out/opt/scidesktop/manifest.d \
    && fetch "https://github.com/nextflow-io/nextflow/releases/download/v${NEXTFLOW_VERSION:?}/nextflow-${NEXTFLOW_VERSION}-dist" \
        "${NEXTFLOW_SHA256:?}" /opt/workflow-engines/bin/nextflow \
    && chmod 0755 /opt/workflow-engines/bin/nextflow \
    && fetch "https://github.com/askimed/nf-test/releases/download/v${NF_TEST_VERSION:?}/nf-test-${NF_TEST_VERSION}.tar.gz" \
        "${NF_TEST_SHA256:?}" /tmp/nf-test.tar.gz \
    && tar -xzf /tmp/nf-test.tar.gz -C /opt/workflow-engines/nf-test \
    && test -f /opt/workflow-engines/nf-test/nf-test.jar \
    && rm -f /tmp/nf-test.tar.gz \
    && micromamba create --yes --root-prefix /tmp/mamba-root --prefix /opt/workflow-engines/snakemake \
        --file "/tmp/$(target-arch conda).lock" \
    && /opt/workflow-engines/snakemake/bin/python -m pip install --no-cache-dir --no-deps --require-hashes \
        --no-compile -r /tmp/requirements.lock \
    && /opt/workflow-engines/snakemake/bin/python -m compileall -q /opt/workflow-engines/snakemake/lib \
    && /opt/workflow-engines/snakemake/bin/python -m pip uninstall --yes pip \
    && rm -rf /tmp/mamba-root /opt/workflow-engines/snakemake/conda-meta/history \
    && ln -s /opt/workflow-engines/bin/nextflow /out/usr/local/bin/nextflow \
    && ln -s /opt/workflow-engines/snakemake/bin/snakemake /out/usr/local/bin/snakemake \
    && smk="$(/opt/workflow-engines/snakemake/bin/python -c 'import importlib.metadata as m; print(m.version("snakemake"))')" \
    && printf '{"nextflow": "%s", "nf-test": "%s", "snakemake": "%s"}\n' \
        "${NEXTFLOW_VERSION}" "${NF_TEST_VERSION}" "${smk}" \
        > /out/opt/scidesktop/manifest.d/workflow-engines.json \
    && chmod -R a+rX,go-w /opt/workflow-engines /out

FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /opt/workflow-engines /opt/workflow-engines
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN set -eu \
    && HOME="$(mktemp -d)" && export HOME \
    && nextflow -version | grep -q "version" \
    && nf-test version | grep -qi "nf-test" \
    && snakemake --version \
    && printf 'rule all:\n    output: "done.txt"\n    shell: "echo smk-ok > {output}"\n' > "${HOME}/Snakefile" \
    && snakemake --snakefile "${HOME}/Snakefile" --directory "${HOME}" --cores 1 \
    && [ "$(cat "${HOME}/done.txt")" = "smk-ok" ]
