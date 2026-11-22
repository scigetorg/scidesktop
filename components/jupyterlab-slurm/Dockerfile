# syntax=docker/dockerfile:1
# Slurm Queue Manager extension for JupyterLab (NERSC/jupyterlab-slurm,
# BSD-3-Clause) at /opt/jupyterlab-slurm, built from a pinned commit against
# the Jupyter environment's JupyterLab. Works alongside components/slurm in
# every desktop image (scidesktop, microdesktop, aidesktop, neurodesktop).

ARG NODE_VERSION
ARG UBUNTU_IMAGE

FROM docker.io/library/node:${NODE_VERSION}-bookworm-slim AS build
ARG JUPYTERLAB_SLURM_COMMIT
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY --from=jupyterlab-slurm-src . /src
COPY patch_jupyterlab_slurm.py /tmp/patch_jupyterlab_slurm.py
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=cache,target=/root/.npm \
    --mount=type=cache,target=/root/.yarn/berry/cache \
    : "${JUPYTERLAB_SLURM_COMMIT:?}" \
    && export PATH="${PATH}:/opt/conda/bin" \
    && /opt/conda/bin/python /tmp/patch_jupyterlab_slurm.py /src/jupyterlab_slurm/handlers.py \
    && cd /src \
    && YARN_ENABLE_IMMUTABLE_INSTALLS=0 jlpm install \
    && jlpm build:lib \
    && jupyter-builder build --core-package-file=/opt/conda/share/jupyter/lab/static/package.json . \
    && labextension=/out/opt/jupyterlab-slurm/lib/share/jupyter/labextensions/jupyterlab-slurm \
    && install -d -m 0755 /out/opt/jupyterlab-slurm/lib "$(dirname "${labextension}")" \
    && cp -r jupyterlab_slurm /out/opt/jupyterlab-slurm/lib/jupyterlab_slurm \
    && mv /out/opt/jupyterlab-slurm/lib/jupyterlab_slurm/labextension "${labextension}" \
    && find /out/opt/jupyterlab-slurm -name __pycache__ -prune -exec rm -rf {} + \
    && test -f "${labextension}/package.json" \
    && find /out/opt/jupyterlab-slurm -name "*.map" -delete \
    && install -m 0644 /src/LICENSE /out/opt/jupyterlab-slurm/LICENSE \
    && install -d -m 0755 /out/usr/local/share/jupyter/labextensions /out/opt/scidesktop/manifest.d \
    && ln -s /opt/jupyterlab-slurm/lib/share/jupyter/labextensions/jupyterlab-slurm \
        /out/usr/local/share/jupyter/labextensions/jupyterlab-slurm \
    && chmod -R a+rX,go-w /out \
    && printf '{"jupyterlab-slurm": "%s"}\n' "${JUPYTERLAB_SLURM_COMMIT}" \
        > /out/opt/scidesktop/manifest.d/jupyterlab-slurm.json

FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,from=jupyter-env,source=/usr/local/etc/jupyter,target=/usr/local/etc/jupyter \
    PATH="/opt/conda/bin:${PATH}" /opt/conda/bin/python -c 'import sys; sys.path.append("/opt/jupyterlab-slurm/lib"); import jupyterlab_slurm, jupyterlab_slurm.handlers as h; assert "scidesktop-slurm-process-identity" in open(h.__file__).read()' \
    && labs="$(PATH="/opt/conda/bin:${PATH}" jupyter labextension list 2>&1)" \
    && printf '%s\n' "${labs}" \
    && printf '%s\n' "${labs}" | grep -q "jupyterlab-slurm .*enabled.*OK" \
    && test -r /opt/scidesktop/manifest.d/jupyterlab-slurm.json
