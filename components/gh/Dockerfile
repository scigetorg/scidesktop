# syntax=docker/dockerfile:1
# gh: GitHub command line. Installed from conda-forge into its own prefix at /opt/gh
# from a lock per architecture, with its command linked onto PATH
# (/usr/local/bin/gh).

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
    micromamba create --yes --root-prefix /tmp/mamba-root --prefix /opt/gh \
        --file "/tmp/$(target-arch conda).lock" \
    && rm -rf /tmp/mamba-root /opt/gh/conda-meta/history /opt/gh/share/man /opt/gh/share/doc \
    && install -d -m 0755 /out/usr/local/bin /out/opt/scidesktop/manifest.d \
    && ln -s /opt/gh/bin/gh /out/usr/local/bin/gh \
    && version="$(ls /opt/gh/conda-meta | sed -n 's/^gh-\([^-]*\)-.*\.json$/\1/p')" \
    && [ -n "${version}" ] \
    && printf '{"gh": "%s"}\n' "${version}" > /out/opt/scidesktop/manifest.d/gh.json \
    && chmod -R a+rX,go-w /opt/gh /out

FROM scratch AS component
COPY --from=build /opt/gh /opt/gh
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN out="$(gh --version)" \
    && grep -q "^gh version" <<<"${out}" \
    && test -r /opt/scidesktop/manifest.d/gh.json
