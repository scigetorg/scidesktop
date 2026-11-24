# syntax=docker/dockerfile:1
# tcsh: C shell, for legacy csh scripts (#!/bin/csh, #!/bin/tcsh). Installed from conda-forge into its own prefix at /opt/tcsh
# from a lock per architecture, with its command linked onto PATH
# (/usr/bin/tcsh, /usr/bin/csh).

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
    micromamba create --yes --root-prefix /tmp/mamba-root --prefix /opt/tcsh \
        --file "/tmp/$(target-arch conda).lock" \
    && rm -rf /tmp/mamba-root /opt/tcsh/conda-meta/history /opt/tcsh/share/man /opt/tcsh/share/doc \
    && install -d -m 0755 /out/usr/bin /out/opt/scidesktop/manifest.d \
    && ln -s /opt/tcsh/bin/tcsh /out/usr/bin/tcsh \
    && ln -s /opt/tcsh/bin/tcsh /out/usr/bin/csh \
    && version="$(ls /opt/tcsh/conda-meta | sed -n 's/^tcsh-\([^-]*\)-.*\.json$/\1/p')" \
    && [ -n "${version}" ] \
    && printf '{"tcsh": "%s"}\n' "${version}" > /out/opt/scidesktop/manifest.d/tcsh.json \
    && chmod -R a+rX,go-w /opt/tcsh /out

FROM scratch AS component
COPY --from=build /opt/tcsh /opt/tcsh
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN [ "$(/bin/csh -c "echo csh-ok")" = csh-ok ] && [ "$(/bin/tcsh -c "echo tcsh-ok")" = tcsh-ok ] \
    && test -r /opt/scidesktop/manifest.d/tcsh.json
