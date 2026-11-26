# syntax=docker/dockerfile:1
# Lightcone (`lc`, lightcone-cli) in an isolated venv at /opt/lightcone, backed
# by jupyter-env's Python so no second runtime is shipped, and kept apart from
# the Jupyter environment because of its Dask dependency graph. /usr/local/bin/lc
# gives it a compute catalog sized to the session's Slurm queue. Included in
# scidesktop (docs/images.md).

ARG UBUNTU_IMAGE
FROM ${UBUNTU_IMAGE} AS build
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# A pin changed without ./lock fails here rather than installing the old lock.
RUN --mount=type=bind,from=components,source=check-lock,target=/usr/local/bin/check-lock \
    --mount=type=bind,source=.,target=/src \
    check-lock /src/requirements.in /src/requirements.lock
COPY requirements.lock /tmp/
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,from=components,source=trim-python-env,target=/usr/local/bin/trim-python-env \
    /opt/conda/bin/python -m venv --without-pip /opt/lightcone \
    && /opt/conda/bin/python -m pip --python /opt/lightcone/bin/python install \
        --no-cache-dir --no-deps --require-hashes --no-compile -r /tmp/requirements.lock \
    && trim-python-env /opt/lightcone \
    && chmod -R a+rX,go-w /opt/lightcone \
    && install -d -m 0755 /out/manifest \
    && /opt/lightcone/bin/python -c 'import json, importlib.metadata as m; json.dump({p: m.version(p) for p in ("lightcone-cli", "astra-tools", "astra-spec", "dask", "distributed")}, open("/out/manifest/lightcone.json", "w"))' \
    && cat /out/manifest/lightcone.json

# Integration files from rootfs/ (the lc command) at their image paths,
# without group or other write permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /opt/lightcone /opt/lightcone
COPY --from=build /out/manifest/ /opt/scidesktop/manifest.d/

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,source=test.sh,target=/tmp/test.sh bash /tmp/test.sh
