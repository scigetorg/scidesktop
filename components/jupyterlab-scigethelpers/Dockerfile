# syntax=docker/dockerfile:1
# Session Helpers panel for JupyterLab at /opt/jupyterlab-scigethelpers:
# a federated JupyterLab extension (Launcher tile under Scidesktop, Command
# Palette entries, and background startup tab on fresh workspaces) backed by
# an authenticated Tornado API wrapping `scigethelpers` (info, check, cite,
# kernel/uv lists). Included in the scidesktop base image.

# Versions come from docker-bake.hcl.
ARG NODE_VERSION
ARG UBUNTU_IMAGE

# JavaScript-only federated extension built against jupyter-env's JupyterLab.
FROM docker.io/library/node:${NODE_VERSION}-bookworm-slim AS build
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY labextension /src/labextension
COPY jupyterlab_scigethelpers /src/jupyterlab_scigethelpers
COPY rootfs /src/rootfs
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=cache,target=/root/.npm \
    export PATH="${PATH}:/opt/conda/bin" \
    && cd /src/labextension \
    && npm ci --no-audit --no-fund \
    && jupyter-builder build --core-package-file=/opt/conda/share/jupyter/lab/static/package.json . \
    && labextension=/out/opt/jupyterlab-scigethelpers/lib/share/jupyter/labextensions/jupyterlab-scigethelpers \
    && install -d -m 0755 /out/opt/jupyterlab-scigethelpers/lib "$(dirname "${labextension}")" \
    && cp -r /src/jupyterlab_scigethelpers/. /out/opt/jupyterlab-scigethelpers/lib/jupyterlab_scigethelpers/ \
    && mv /src/labextension/labextension "${labextension}" \
    && find /out/opt/jupyterlab-scigethelpers -name __pycache__ -prune -exec rm -rf {} + \
    && find /out/opt/jupyterlab-scigethelpers -name "*.map" -delete \
    && test -f "${labextension}/package.json" \
    && test -f "${labextension}/schemas/jupyterlab-scigethelpers/plugin.json" \
    && install -d -m 0755 /out/usr/local/share/jupyter/labextensions /out/opt/scidesktop/manifest.d \
    && ln -s /opt/jupyterlab-scigethelpers/lib/share/jupyter/labextensions/jupyterlab-scigethelpers \
        /out/usr/local/share/jupyter/labextensions/jupyterlab-scigethelpers \
    && chmod -R a+rX,go-w /out \
    && hash="$(find /src/jupyterlab_scigethelpers /src/rootfs /src/labextension/lib /src/labextension/schema /src/labextension/style /src/labextension/package.json /src/labextension/package-lock.json \
        -type f -print | LC_ALL=C sort | xargs sha256sum | sha256sum | cut -d ' ' -f 1)" \
    && printf '{"extension_sha256": "%s"}\n' "${hash}" \
        > /out/opt/scidesktop/manifest.d/jupyterlab-scigethelpers.json

# Integration files from rootfs/ at their image paths, readable and without
# group or other write permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /out/ /

# Runs a real Jupyter server with this component's config and scigethelpers-cli
# under a nested base_url to verify auth, XSRF/Origin, API contracts, and assets.
FROM os AS test
COPY --from=scigethelpers-cli / /
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,from=jupyter-env,source=/etc/jupyter,target=/etc/jupyter \
    --mount=type=bind,from=jupyter-env,source=/usr/local/etc/jupyter,target=/usr/local/etc/jupyter \
    --mount=type=bind,from=tests,source=jupyterlab-scigethelpers-check.py,target=/tmp/jupyterlab-scigethelpers-check.py \
    --mount=type=bind,source=test.sh,target=/tmp/test.sh \
    bash /tmp/test.sh
