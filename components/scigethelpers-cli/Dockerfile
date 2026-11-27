# syntax=docker/dockerfile:1
# The `scigethelpers` command at /opt/scigethelpers-cli: `scigethelpers cite`,
# `scigethelpers kernel`, `scigethelpers uv`, `scigethelpers check`,
# `scigethelpers info` and `scigethelpers agent preflight`, generalized from
# neurodesk/neurodesktop's CLI (MIT) to work across sciget domain images.
# Included in the scidesktop base image (images/scidesktop/Dockerfile).
# Python scripts for the Jupyter environment's interpreter and an Lmod site
# package; no software of its own.

ARG UBUNTU_IMAGE

# Integration files from rootfs/ at their image paths, readable and without
# group or other write permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY rootfs/ /rootfs/
# The manifest identifies the command by content, so any change to its scripts,
# wrapper, Lmod site package or Bash completion shows in an image's manifest.
# `scigethelpers --version` prints it.
RUN chmod -R a+rX,go-w /rootfs \
    && install -d -m 0755 /rootfs/opt/scidesktop/manifest.d \
    && hash="$(find /rootfs/opt/scigethelpers-cli /rootfs/etc/bash.bashrc.d/scigethelpers-cli.sh \
        -type f -print | LC_ALL=C sort | xargs sha256sum | sha256sum | cut -d ' ' -f 1)" \
    && printf '{"cli_sha256": "%s"}\n' "${hash}" \
        > /rootfs/opt/scidesktop/manifest.d/scigethelpers-cli.json

FROM scratch AS component
COPY --from=rootfs /rootfs/ /

# On the OS layer with Lmod and the session's Slurm queue, and the Jupyter
# environment's Python, which the commands run with.
FROM os AS test
COPY --from=lmod / /
COPY --from=slurm / /
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,source=test.sh,target=/tmp/test.sh bash /tmp/test.sh
