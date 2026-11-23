# syntax=docker/dockerfile:1
# microdesktop: scidesktop for microscopy.
#
# `docker buildx bake microdesktop` builds scidesktop from this repository and
# passes it in as `scidesktop-base` below; nothing is pulled from a registry.
# A plain `docker build` of this folder fails, because no image of that name
# exists outside bake.
#
# Configures sciget's system layer to offer the published microscopy tool
# catalog (with CVMFS container lookup under /cvmfs/neurodesk.ardc.edu.au/containers).
# Changes every image needs belong in the base (components/), not here; see
# docs/images.md.

FROM scidesktop-base

USER root
COPY --chmod=0644 catalogs.json /etc/sciget/catalogs.json
USER ${NB_UID}

LABEL org.opencontainers.image.title="microdesktop" \
      org.opencontainers.image.description="scidesktop for microscopy with the microscopy sciget tool catalog"
