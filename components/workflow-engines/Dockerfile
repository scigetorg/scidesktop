# syntax=docker/dockerfile:1
# Generic scientific workflow engines at /opt/workflow-engines, shared across
# all desktops (scidesktop, microdesktop, datadesktop, neurodesktop, genomicsdesktop, ...):
#   - Nextflow (Apache-2.0): offline fat distribution executable
#   - nf-test (MIT): test runner JAR for Nextflow pipelines
#   - Viash (GPL-3.0): standalone JVM executable for modular pipeline components
#   - Snakemake (MIT): isolated locked venv backed by jupyter-env's Python 3.13
#   - Java for Nextflow, nf-test and Viash: the Eclipse Temurin 21 runtime at
#     /opt/workflow-engines/jre; java, keytool and rmiregistry on PATH

ARG UBUNTU_IMAGE
FROM ${UBUNTU_IMAGE} AS build
ARG TARGETARCH
ARG APT_CACHE_ID
ARG NEXTFLOW_VERSION
ARG NEXTFLOW_SHA256
ARG NF_TEST_VERSION
ARG NF_TEST_SHA256
ARG VIASH_VERSION
ARG VIASH_SHA256
ARG TEMURIN_JRE_VERSION
ARG TEMURIN_JRE_SHA256_AMD64
ARG TEMURIN_JRE_SHA256_ARM64
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=private \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=private \
    apt-get update && apt-get install --no-install-recommends -y ca-certificates curl
RUN --mount=type=bind,from=components,source=check-lock,target=/usr/local/bin/check-lock \
    --mount=type=bind,source=.,target=/src \
    check-lock /src/requirements.in /src/requirements.lock
COPY requirements.lock /tmp/
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,from=components,source=fetch,target=/usr/local/bin/fetch \
    --mount=type=bind,from=components,source=trim-python-env,target=/usr/local/bin/trim-python-env \
    install -d -m 0755 /opt/workflow-engines/bin /opt/workflow-engines/nf-test /opt/workflow-engines/viash \
        /out/usr/local/bin /out/opt/scidesktop/manifest.d \
    && fetch "https://github.com/nextflow-io/nextflow/releases/download/v${NEXTFLOW_VERSION:?}/nextflow-${NEXTFLOW_VERSION}-dist" \
        "${NEXTFLOW_SHA256:?}" /opt/workflow-engines/bin/nextflow \
    && chmod 0755 /opt/workflow-engines/bin/nextflow \
    && fetch "https://github.com/viash-io/viash/releases/download/${VIASH_VERSION:?}/viash" \
        "${VIASH_SHA256:?}" /opt/workflow-engines/viash/viash \
    && chmod 0755 /opt/workflow-engines/viash/viash \
    # Temurin names the architectures x64 and aarch64, and the files after the
    # release with _ for +.
    && case "${TARGETARCH}" in \
        amd64) jre_arch=x64 ;; \
        arm64) jre_arch=aarch64 ;; \
        *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && jre_sha256="TEMURIN_JRE_SHA256_${TARGETARCH^^}" \
    && jre_file="OpenJDK21U-jre_${jre_arch}_linux_hotspot_${TEMURIN_JRE_VERSION//+/_}.tar.gz" \
    && fetch "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-${TEMURIN_JRE_VERSION//+/%2B}/${jre_file}" \
        "${!jre_sha256:?}" /tmp/jre.tar.gz \
    && install -d -m 0755 /opt/workflow-engines/jre \
    && tar -xzf /tmp/jre.tar.gz -C /opt/workflow-engines/jre --strip-components=1 \
    && rm -f /tmp/jre.tar.gz \
    && java_ver="$(/opt/workflow-engines/jre/bin/java -version 2>&1)" \
    && grep -q '"21\.' <<<"${java_ver}" \
    && for t in java keytool rmiregistry; do ln -s "/opt/workflow-engines/jre/bin/${t}" "/out/usr/local/bin/${t}"; done \
    && fetch "https://github.com/askimed/nf-test/releases/download/v${NF_TEST_VERSION:?}/nf-test-${NF_TEST_VERSION}.tar.gz" \
        "${NF_TEST_SHA256:?}" /tmp/nf-test.tar.gz \
    && tar -xzf /tmp/nf-test.tar.gz -C /opt/workflow-engines/nf-test \
    && test -f /opt/workflow-engines/nf-test/nf-test.jar \
    && rm -f /tmp/nf-test.tar.gz \
    && /opt/conda/bin/python -m venv --without-pip /opt/workflow-engines/snakemake \
    && /opt/conda/bin/python -m pip --python /opt/workflow-engines/snakemake/bin/python install \
        --no-cache-dir --no-deps --require-hashes --no-compile -r /tmp/requirements.lock \
    && trim-python-env /opt/workflow-engines/snakemake \
    && ln -s /opt/workflow-engines/bin/nextflow /out/usr/local/bin/nextflow \
    && ln -s /opt/workflow-engines/snakemake/bin/snakemake /out/usr/local/bin/snakemake \
    && smk="$(/opt/workflow-engines/snakemake/bin/python -c 'import importlib.metadata as m; print(m.version("snakemake"))')" \
    && smk_slurm="$(/opt/workflow-engines/snakemake/bin/python -c 'import importlib.metadata as m; print(m.version("snakemake-executor-plugin-slurm"))')" \
    && printf '{"nextflow": "%s", "nf-test": "%s", "viash": "%s", "temurin-jre": "%s", "snakemake": "%s", "snakemake-executor-plugin-slurm": "%s"}\n' \
        "${NEXTFLOW_VERSION}" "${NF_TEST_VERSION}" "${VIASH_VERSION}" "${TEMURIN_JRE_VERSION}" "${smk}" "${smk_slurm}" \
        > /out/opt/scidesktop/manifest.d/workflow-engines.json \
    && chmod -R a+rX,go-w /opt/workflow-engines /out

FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs \
    && chmod 0755 /rootfs/usr/local/bin/nf-test /rootfs/usr/local/bin/viash

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /opt/workflow-engines /opt/workflow-engines
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
# System CA integration: an institutional CA added through Ubuntu's
# update-ca-certificates reaches the bundled Temurin JRE trust store and is
# removed again cleanly.
RUN set -eu \
    && /opt/workflow-engines/jre/bin/keytool -genkeypair -noprompt -alias testca \
        -keyalg RSA -keysize 2048 -dname "CN=Scidesktop Test CA" -ext bc:c \
        -keystore /tmp/test-ca.p12 -storepass changeit >/dev/null 2>&1 \
    && /opt/workflow-engines/jre/bin/keytool -exportcert -rfc -alias testca \
        -keystore /tmp/test-ca.p12 -storepass changeit \
        -file /usr/local/share/ca-certificates/scidesktop-test-ca.crt >/dev/null 2>&1 \
    && update-ca-certificates >/dev/null \
    && alias="system-ca:$(printf '%s' /etc/ssl/certs/scidesktop-test-ca.pem | sha256sum | cut -c1-16)" \
    && /opt/workflow-engines/jre/bin/keytool -list -cacerts -storepass changeit -alias "${alias}" >/dev/null \
    && rm -f /usr/local/share/ca-certificates/scidesktop-test-ca.crt /tmp/test-ca.p12 \
    && update-ca-certificates --fresh >/dev/null \
    && ! /opt/workflow-engines/jre/bin/keytool -list -cacerts -storepass changeit -alias "${alias}" >/dev/null 2>&1 \
    && [ "$(/opt/workflow-engines/jre/bin/keytool -list -cacerts -storepass changeit | grep -c ', trustedCertEntry,')" -ge 50 ]
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    set -eu \
    && HOME="$(mktemp -d)" && export HOME && cd "${HOME}" \
    && [ "$(readlink -f "$(command -v java)")" = /opt/workflow-engines/jre/bin/java ] \
    && nf_ver="$(nextflow -version)" && grep -q "version" <<<"${nf_ver}" \
    && nft_ver="$(nf-test version)" && grep -qi "nf-test" <<<"${nft_ver}" \
    && vsh_ver="$(viash --version)" && grep -qi "viash" <<<"${vsh_ver}" \
    && test -r /etc/scidesktop/nextflow/scidesktop.config \
    && mkdir -p "${HOME}/vsh" \
    && printf 'name: greet\narguments:\n  - name: --name\n    type: string\n    default: world\n  - name: --output\n    type: file\n    direction: output\n    required: true\nresources:\n  - type: bash_script\n    path: script.sh\nengines:\n  - type: native\nrunners:\n  - type: executable\n  - type: nextflow\n' > "${HOME}/vsh/config.vsh.yaml" \
    && printf '#!/bin/bash\nset -euo pipefail\necho "hello-${par_name}" > "${par_output}"\n' > "${HOME}/vsh/script.sh" \
    && viash run "${HOME}/vsh/config.vsh.yaml" -- --name test --output "${HOME}/vsh-run.txt" \
    && [ "$(cat "${HOME}/vsh-run.txt")" = "hello-test" ] \
    && viash build "${HOME}/vsh/config.vsh.yaml" --runner executable --output "${HOME}/vsh-exe" \
    && "${HOME}/vsh-exe/greet" --name exe --output "${HOME}/vsh-exe.txt" \
    && [ "$(cat "${HOME}/vsh-exe.txt")" = "hello-exe" ] \
    && viash build "${HOME}/vsh/config.vsh.yaml" --runner nextflow --output "${HOME}/vsh-nf" \
    && test -f "${HOME}/vsh-nf/main.nf" \
    && NXF_OFFLINE=true NXF_SYNTAX_PARSER=v1 nextflow run "${HOME}/vsh-nf/main.nf" \
        -c /etc/scidesktop/nextflow/scidesktop.config -profile apptainer \
        -work-dir "${HOME}/vsh-nf-work" \
        --id s1 --name nf --output out.txt --publish_dir "${HOME}/vsh-nf-out" \
    && [ "$(cat "${HOME}/vsh-nf-out/out.txt")" = "hello-nf" ] \
    && snakemake --version \
    && snakemake --executor slurm --help >/dev/null \
    && printf 'rule all:\n    output: "done.txt"\n    shell: "echo smk-ok > {output}"\n' > "${HOME}/Snakefile" \
    && snakemake --snakefile "${HOME}/Snakefile" --directory "${HOME}" --cores 1 \
    && [ "$(cat "${HOME}/done.txt")" = "smk-ok" ]
