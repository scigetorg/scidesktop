# syntax=docker/dockerfile:1
# micromamba, the installer the conda-based components (jupyter-env, selkies) build
# their environments with. Version and checksum come from docker-bake.hcl.

FROM scratch AS component
ARG MICROMAMBA_VERSION
ARG MICROMAMBA_SHA256
ADD --chmod=0755 --checksum=sha256:${MICROMAMBA_SHA256} \
    https://github.com/mamba-org/micromamba-releases/releases/download/${MICROMAMBA_VERSION}/micromamba-linux-64 \
    /usr/local/bin/micromamba

FROM os AS test
COPY --from=component / /
RUN micromamba --version
