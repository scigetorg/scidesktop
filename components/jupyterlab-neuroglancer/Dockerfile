# syntax=docker/dockerfile:1
# Neuroglancer for JupyterLab at /opt/jupyterlab-neuroglancer: an interactive
# WebGL2 viewer for OME-Zarr (Zarr v2/v3), N5, Precomputed, NIfTI and mesh
# datasets, opened from the JupyterLab launcher or file browser context menu.
# Builds the official standalone Google Neuroglancer client (Apache-2.0) from
# a pinned commit and packages a JupyterLab federated extension plus an
# authenticated server extension outside /opt/conda so the component stays
# optional (copied by microdesktop; see docs/viewers.md).

# Versions come from docker-bake.hcl.
ARG NODE_VERSION
ARG UBUNTU_IMAGE

# JavaScript/WASM only: the built static client and JupyterLab extension are
# architecture-independent. JupyterLab's own builder comes from jupyter-env.
FROM docker.io/library/node:${NODE_VERSION}-bookworm-slim AS build
ARG NEUROGLANCER_COMMIT
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY --from=neuroglancer-src . /src/neuroglancer
COPY labextension /src/labextension
COPY jupyterlab_neuroglancer /src/jupyterlab_neuroglancer
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=cache,target=/root/.npm \
    : "${NEUROGLANCER_COMMIT:?}" \
    && export PATH="${PATH}:/opt/conda/bin" \
    # 1. Build the official standalone Neuroglancer web client (exact npm lockfile).
    && cd /src/neuroglancer \
    && npm ci --no-audit --no-fund \
    && static_dir=/out/opt/jupyterlab-neuroglancer/lib/jupyterlab_neuroglancer/static/neuroglancer \
    && install -d -m 0755 "${static_dir}" \
    && npm run build -- --no-typecheck --no-lint --output "${static_dir}" \
    && test -f "${static_dir}/index.html" \
    # 2. Build the JupyterLab federated extension against jupyter-env's JupyterLab.
    && cd /src/labextension \
    && npm ci --no-audit --no-fund \
    && jupyter-builder build --core-package-file=/opt/conda/share/jupyter/lab/static/package.json . \
    # 3. Assemble the Python server extension and labextension layout.
    && labextension=/out/opt/jupyterlab-neuroglancer/lib/share/jupyter/labextensions/jupyterlab-neuroglancer \
    && install -d -m 0755 /out/opt/jupyterlab-neuroglancer/lib "$(dirname "${labextension}")" \
    && cp -r /src/jupyterlab_neuroglancer/. /out/opt/jupyterlab-neuroglancer/lib/jupyterlab_neuroglancer/ \
    && mv /src/labextension/labextension "${labextension}" \
    && find /out/opt/jupyterlab-neuroglancer -name __pycache__ -prune -exec rm -rf {} + \
    && find /out/opt/jupyterlab-neuroglancer -name "*.map" -delete \
    && test -f "${labextension}/package.json" \
    && test -f "${static_dir}/index.html" \
    && install -m 0644 /src/neuroglancer/LICENSE /out/opt/jupyterlab-neuroglancer/LICENSE \
    # JupyterLab discovers federated extensions under /usr/local/share/jupyter/labextensions.
    && install -d -m 0755 /out/usr/local/share/jupyter/labextensions /out/opt/scidesktop/manifest.d \
    && ln -s /opt/jupyterlab-neuroglancer/lib/share/jupyter/labextensions/jupyterlab-neuroglancer \
        /out/usr/local/share/jupyter/labextensions/jupyterlab-neuroglancer \
    && chmod -R a+rX,go-w /out \
    && printf '{"neuroglancer": "%s"}\n' "${NEUROGLANCER_COMMIT}" \
        > /out/opt/scidesktop/manifest.d/jupyterlab-neuroglancer.json

# Integration files from rootfs/ at their image paths, readable and without
# group or other write permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /out/ /

# The viewer is served by the notebook server, so the test borrows the
# Jupyter environment and runs a server with this component's configuration.
FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,from=jupyter-env,source=/etc/jupyter,target=/etc/jupyter \
    --mount=type=bind,from=jupyter-env,source=/usr/local/etc/jupyter,target=/usr/local/etc/jupyter \
    --mount=type=bind,from=tests,source=viewer-check.py,target=/tmp/viewer-check.py \
    --mount=type=bind,from=components,source=viewer-test,target=/tmp/viewer-test \
    bash /tmp/viewer-test jupyterlab-neuroglancer
