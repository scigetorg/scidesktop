# syntax=docker/dockerfile:1
# aria2: multi-connection downloader. Installed from conda-forge into its own prefix at /opt/aria2
# from a lock per architecture, with its command linked onto PATH
# (/usr/local/bin/aria2c).

ARG UBUNTU_IMAGE
FROM ${UBUNTU_IMAGE} AS build
ARG TARGETARCH
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get install --no-install-recommends -y ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# A pin changed without ./lock fails here rather than installing the old lock.
RUN --mount=type=bind,from=components,source=check-lock,target=/usr/local/bin/check-lock \
    --mount=type=bind,source=.,target=/src \
    check-lock /src/environment.yml /src/linux-*.lock
COPY --from=micromamba /usr/local/bin/micromamba /usr/local/bin/micromamba
COPY linux-*.lock /tmp/
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    micromamba create --yes --root-prefix /tmp/mamba-root --prefix /opt/aria2 \
        --file "/tmp/$(target-arch conda).lock" \
    && rm -rf /tmp/mamba-root /opt/aria2/conda-meta/history /opt/aria2/share/man /opt/aria2/share/doc \
    # Point conda-forge's OpenSSL bundle at the OS trust store so institutional
    # CAs added through update-ca-certificates reach aria2c.
    && ln -sf /etc/ssl/certs/ca-certificates.crt /opt/aria2/ssl/cacert.pem \
    && install -d -m 0755 /out/usr/local/bin /out/opt/scidesktop/manifest.d \
    && ln -s /opt/aria2/bin/aria2c /out/usr/local/bin/aria2c \
    && version="$(ls /opt/aria2/conda-meta | sed -n 's/^aria2-\([^-]*\)-.*\.json$/\1/p')" \
    && [ -n "${version}" ] \
    && printf '{"aria2": "%s"}\n' "${version}" > /out/opt/scidesktop/manifest.d/aria2.json \
    && chmod -R a+rX,go-w /opt/aria2 /out

FROM scratch AS component
COPY --from=build /opt/aria2 /opt/aria2
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN aria2c --version | head -1 | grep -q "aria2 version" \
    && [ "$(readlink -f /opt/aria2/ssl/cert.pem)" = /etc/ssl/certs/ca-certificates.crt ] \
    && test -s /opt/aria2/ssl/cert.pem \
    && test -r /opt/scidesktop/manifest.d/aria2.json
