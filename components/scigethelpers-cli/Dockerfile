# syntax=docker/dockerfile:1
# The `scigethelpers` command at /opt/scigethelpers-cli: `scigethelpers cite`,
# `scigethelpers kernel`, `scigethelpers check` and `scigethelpers info`,
# generalized from neurodesk/neurodesktop's CLI (MIT) to work across sciget
# domain images (neurodesktop, microdesktop, and others). Python scripts for
# the Jupyter environment's interpreter and an Lmod site package; no software of
# its own. Not part of the base image; domain images copy it (docs/images.md).

ARG UBUNTU_IMAGE

# Integration files from rootfs/ at their image paths, readable and without
# group or other write permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY rootfs/ /rootfs/
# The manifest identifies the command by content, so a change to it shows in
# an image's manifest. `scigethelpers --version` prints it.
RUN chmod -R a+rX,go-w /rootfs \
    && install -d -m 0755 /rootfs/opt/scidesktop/manifest.d \
    && printf '{"cli_sha256": "%s"}\n' \
        "$(cat /rootfs/opt/scigethelpers-cli/lib/*.py | sha256sum | cut -d ' ' -f 1)" \
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
