# syntax=docker/dockerfile:1
# rclone: cloud storage sync and transfer (S3, WebDAV, SFTP, Google Drive and more). Installed from conda-forge into its own prefix at /opt/rclone
# from a lock per architecture, with its command linked onto PATH
# (/usr/local/bin/rclone).

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
    micromamba create --yes --root-prefix /tmp/mamba-root --prefix /opt/rclone \
        --file "/tmp/$(target-arch conda).lock" \
    && rm -rf /tmp/mamba-root /opt/rclone/conda-meta/history /opt/rclone/share/man /opt/rclone/share/doc \
    && install -d -m 0755 /out/usr/local/bin /out/opt/scidesktop/manifest.d \
    && ln -s /opt/rclone/bin/rclone /out/usr/local/bin/rclone \
    && version="$(ls /opt/rclone/conda-meta | sed -n 's/^rclone-\([^-]*\)-.*\.json$/\1/p')" \
    && [ -n "${version}" ] \
    && printf '{"rclone": "%s"}\n' "${version}" > /out/opt/scidesktop/manifest.d/rclone.json \
    && chmod -R a+rX,go-w /opt/rclone /out

FROM scratch AS component
COPY --from=build /opt/rclone /opt/rclone
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN out="$(rclone version)" \
    && grep -q "^rclone v" <<<"${out}" \
    && test -r /opt/scidesktop/manifest.d/rclone.json
