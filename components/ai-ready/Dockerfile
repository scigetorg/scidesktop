# syntax=docker/dockerfile:1
# Intersect Australia's AI Ready workshop at /opt/ai-ready: a notebook kernel
# with the workshop's libraries, Airflow, MLflow and PostgreSQL, and the hook
# that runs them beside the notebook server. Not part of the base image;
# domain images copy it (docs/images.md).

# Built from the plain Ubuntu image, not the OS layer: the output depends only
# on the lockfiles and the upstream commit, so OS updates do not rebuild it.
ARG UBUNTU_IMAGE
FROM ${UBUNTU_IMAGE} AS build
ARG AI_READY_COMMIT
ARG TARGETARCH
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get install --no-install-recommends -y ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# A pin or the upstream commit changed without ./lock fails here rather than
# installing the old locks.
RUN --mount=type=bind,from=components,source=check-lock,target=/usr/local/bin/check-lock \
    --mount=type=bind,source=.,target=/src \
    check-lock /src/environment.yml /src/linux-*.lock \
    && check-lock /src/requirements.in /src/requirements.lock \
    && check-lock /src/airflow-requirements.in /src/airflow-requirements.lock \
    && for lock in requirements.lock airflow-requirements.lock; do \
        grep -q "ai-ready-containers@${AI_READY_COMMIT:?}\." "/src/${lock}" \
            || { echo "check-lock: ${lock} was not made for ai-ready-containers@${AI_READY_COMMIT}; run ./lock" >&2; exit 1; }; \
    done
COPY --from=micromamba /usr/local/bin/micromamba /usr/local/bin/micromamba
COPY linux-*.lock requirements.lock airflow-requirements.lock /tmp/
# Two environments on one interpreter: the workshop kernel (which also runs
# MLflow) and Airflow, whose dependency set would otherwise fight the
# notebook libraries.
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    micromamba create --yes --root-prefix /tmp/mamba-root --prefix /opt/ai-ready/env \
        --file "/tmp/$(target-arch conda).lock" \
    && /opt/ai-ready/env/bin/python -m pip install --no-cache-dir --no-deps --require-hashes \
        --only-binary :all: --no-compile -r /tmp/requirements.lock \
    && /opt/ai-ready/env/bin/python -m venv --without-pip /opt/ai-ready/airflow \
    && /opt/ai-ready/env/bin/python -m pip --python /opt/ai-ready/airflow/bin/python install \
        --no-cache-dir --no-deps --require-hashes --only-binary :all: --no-compile \
        -r /tmp/airflow-requirements.lock \
    && /opt/ai-ready/env/bin/python -m compileall -q /opt/ai-ready/env/lib /opt/ai-ready/airflow/lib \
    # The kernelspec, moved to Jupyter's system folder below. Jupyter fills in ${HOME}
    # and ${PATH} when it starts the kernel: the workshop's own modules import
    # from any notebook, and `!pip` and `!mlflow` are this environment's.
    && /opt/ai-ready/env/bin/python -m ipykernel install --prefix /opt/ai-ready --name ai-ready \
        --display-name "AI Ready (Python $(/opt/ai-ready/env/bin/python -c 'import sys; print("%d.%d" % sys.version_info[:2])'))" \
        --env PYTHONPATH '${HOME}/ai-ready/src' --env PATH '/opt/ai-ready/env/bin:${PATH}' \
    # conda packages carry group-writable modes; nothing root-owned here should
    # be writable by a group.
    && chmod -R go-w /opt/ai-ready \
    && rm -rf /tmp/mamba-root /opt/ai-ready/env/conda-meta/history

# What the image takes from the upstream repository: the workshop content,
# seeded into each home by startup's home-defaults hook, and the few files the
# services need.
FROM build AS upstream
ARG AI_READY_COMMIT
COPY --from=ai-ready-src content/ /out/etc/scidesktop/home-defaults/ai-ready/
COPY --from=ai-ready-src LICENSE docker/airflow/variables.json /out/opt/ai-ready/upstream/
COPY --from=ai-ready-src docker/nginx/html/img/airflow.svg docker/nginx/html/img/mlflow.svg /out/opt/ai-ready/upstream/icons/
RUN --mount=type=bind,source=prepare.py,target=/tmp/prepare.py \
    install -d -m 0755 /out/opt/scidesktop/manifest.d \
    && /opt/ai-ready/env/bin/python /tmp/prepare.py /out/etc/scidesktop/home-defaults/ai-ready \
        "${AI_READY_COMMIT:?}" /out/opt/scidesktop/manifest.d/ai-ready.json \
    && printf '%s\n' "${AI_READY_COMMIT}" > /out/opt/ai-ready/upstream/REVISION \
    && chmod -R a+rX,go-w /out

# Integration files from rootfs/ (the hook, Jupyter config, the supervisor) at
# their image paths, readable and without group or other write permission
# whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

# The kernelspec goes where Jupyter looks without being told
# (/usr/local/share/jupyter), so an image that copies the component sets
# nothing for it.
FROM build AS kernel
RUN install -d -m 0755 /out/usr/local/share/jupyter \
    && mv /opt/ai-ready/share/jupyter/kernels /out/usr/local/share/jupyter/kernels \
    && rmdir /opt/ai-ready/share/jupyter /opt/ai-ready/share

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=kernel /opt/ai-ready /opt/ai-ready
COPY --from=kernel /out/ /
COPY --from=upstream /out/ /

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,source=test.sh,target=/tmp/test.sh bash /tmp/test.sh
