# syntax=docker/dockerfile:1
# FreeBrowse for JupyterLab at /opt/jupyterlab-freebrowse: a viewer for NIfTI
# volumes and NiiVue documents, opened from the file browser. Built from
# Neurodesk's fork of FreeBrowse (BSD-2-Clause; its Jupyter extension MIT) at
# a pinned commit, as neurodesktop builds it: the fork has no release. It
# holds a JupyterLab extension and a server extension that serves the viewer
# behind the notebook server's login; both are installed outside the Jupyter
# environment, so the component stays optional. Not part of the base image;
# domain images copy it (docs/images.md).

# Versions come from docker-bake.hcl.
ARG NODE_VERSION
ARG UBUNTU_IMAGE

# JavaScript only: the result is the same on every architecture. JupyterLab's
# own build tools (jlpm, jupyter-builder) come from the Jupyter environment,
# so the extension is built against the JupyterLab the image runs.
FROM docker.io/library/node:${NODE_VERSION}-bookworm-slim AS build
ARG FREEBROWSE_COMMIT
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY --from=freebrowse-src . /src
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=cache,target=/root/.npm \
    --mount=type=cache,target=/root/.yarn/berry/cache \
    : "${FREEBROWSE_COMMIT:?}" \
    && export PATH="${PATH}:/opt/conda/bin" \
    # The viewer itself, built to run without a backend, into the Python
    # package's static folder. npm installs exactly its lock file.
    && cd /src/frontend \
    && npm ci --no-audit --no-fund \
    && npm run build:jupyter \
    && test -f /src/jupyter/jupyterlab_freebrowse/static/freebrowse/index.html \
    # FreeBrowse registers itself as the default viewer of NIfTI files. It
    # stays the default for its own NiiVue documents and is offered for
    # NIfTI under "Open With", so an image with another NIfTI viewer has one
    # default. The registration must be there exactly once, or the build stops.
    && [ "$(grep -c 'defaultFor: \["nifti", "nifti-gz", "nvd"\],' /src/jupyter/src/index.ts)" = 1 ] \
    && sed -i 's/defaultFor: \["nifti", "nifti-gz", "nvd"\],/defaultFor: ["nvd"],/' /src/jupyter/src/index.ts \
    # The JupyterLab extension. Upstream's yarn.lock does not cover every
    # package, so yarn may complete it.
    && cd /src/jupyter \
    && YARN_ENABLE_IMMUTABLE_INSTALLS=0 jlpm install \
    && jlpm build:lib \
    && jupyter-builder build --core-package-file=/opt/conda/share/jupyter/lab/static/package.json . \
    # The Python package is two modules and the files they serve. It is laid
    # out as its wheel would be, without building one: that would download
    # an unpinned build backend. The package's own switch for the server
    # extension is left out; the component's part of the notebook server's
    # configuration turns it on.
    && labextension=/out/opt/jupyterlab-freebrowse/lib/share/jupyter/labextensions/jupyterlab-freebrowse \
    && install -d -m 0755 /out/opt/jupyterlab-freebrowse/lib "$(dirname "${labextension}")" \
    && cp -r jupyterlab_freebrowse /out/opt/jupyterlab-freebrowse/lib/jupyterlab_freebrowse \
    && mv /out/opt/jupyterlab-freebrowse/lib/jupyterlab_freebrowse/labextension "${labextension}" \
    && find /out/opt/jupyterlab-freebrowse -name __pycache__ -prune -exec rm -rf {} + \
    && test -f "${labextension}/package.json" \
    && test -f /out/opt/jupyterlab-freebrowse/lib/jupyterlab_freebrowse/static/freebrowse/index.html \
    && find /out/opt/jupyterlab-freebrowse -name "*.map" -delete \
    && install -m 0644 /src/LICENSE /out/opt/jupyterlab-freebrowse/LICENSE \
    # JupyterLab looks for extensions here without being told.
    && install -d -m 0755 /out/usr/local/share/jupyter/labextensions /out/opt/scidesktop/manifest.d \
    && ln -s /opt/jupyterlab-freebrowse/lib/share/jupyter/labextensions/jupyterlab-freebrowse \
        /out/usr/local/share/jupyter/labextensions/jupyterlab-freebrowse \
    && chmod -R a+rX,go-w /out \
    && printf '{"freebrowse": "%s"}\n' "${FREEBROWSE_COMMIT}" \
        > /out/opt/scidesktop/manifest.d/jupyterlab-freebrowse.json

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
    --mount=type=bind,from=jupyter-env,source=/usr/local/etc/jupyter,target=/usr/local/etc/jupyter \
    --mount=type=bind,from=tests,source=viewer-check.py,target=/tmp/viewer-check.py \
    --mount=type=bind,from=components,source=viewer-test,target=/tmp/viewer-test \
    bash /tmp/viewer-test jupyterlab-freebrowse
