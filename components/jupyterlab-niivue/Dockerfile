# syntax=docker/dockerfile:1
# The NiiVue viewer for JupyterLab (jupyterlab-niivue, BSD-2-Clause) at
# /opt/jupyterlab-niivue: double-clicking a NIfTI file in the file browser
# opens it. The published wheel, unmodified. It holds a JupyterLab extension
# and a small server extension that serves the viewer's files; both are
# installed outside the Jupyter environment, so the component stays optional.
# Not part of the base image; domain images copy it (docs/images.md).

# Versions and checksums come from docker-bake.hcl.
ARG UBUNTU_IMAGE

FROM ${UBUNTU_IMAGE} AS build
ARG JUPYTERLAB_NIIVUE_VERSION
ARG JUPYTERLAB_NIIVUE_SHA256
ARG TARGETARCH
ARG APT_CACHE_ID
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y curl ca-certificates
# The wheel is pure Python and prebuilt JavaScript: one file for every
# architecture. pip only unpacks it (no index, no dependencies, no build); it
# needs jupyter-server, which the Jupyter environment has.
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,from=components,source=fetch,target=/usr/local/bin/fetch \
    : "${JUPYTERLAB_NIIVUE_VERSION:?}" "${JUPYTERLAB_NIIVUE_SHA256:?}" \
    && wheel="jupyterlab_niivue-${JUPYTERLAB_NIIVUE_VERSION}-py3-none-any.whl" \
    && fetch "https://files.pythonhosted.org/packages/py3/j/jupyterlab_niivue/${wheel}" \
        "${JUPYTERLAB_NIIVUE_SHA256}" "/tmp/${wheel}" \
    && /opt/conda/bin/python -m pip install --no-deps --no-index --no-compile --no-cache-dir \
        --target /out/opt/jupyterlab-niivue/lib "/tmp/${wheel}" \
    && labextension=/out/opt/jupyterlab-niivue/lib/share/jupyter/labextensions/@niivue/jupyter \
    && test -f "${labextension}/package.json" \
    && test -d /out/opt/jupyterlab-niivue/lib/jupyterlab_niivue/labextension/static \
    && find /out/opt/jupyterlab-niivue -name "*.map" -delete \
    # JupyterLab looks for extensions here without being told.
    && install -d -m 0755 "/out/usr/local/share/jupyter/labextensions/@niivue" /out/opt/scidesktop/manifest.d \
    && ln -s /opt/jupyterlab-niivue/lib/share/jupyter/labextensions/@niivue/jupyter \
        "/out/usr/local/share/jupyter/labextensions/@niivue/jupyter" \
    && chmod -R a+rX,go-w /out \
    && printf '{"jupyterlab-niivue": "%s"}\n' "${JUPYTERLAB_NIIVUE_VERSION}" \
        > /out/opt/scidesktop/manifest.d/jupyterlab-niivue.json

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
    bash /tmp/viewer-test jupyterlab-niivue
