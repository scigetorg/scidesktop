# syntax=docker/dockerfile:1
# microdesktop: scidesktop for microscopy.
#
# `docker buildx bake microdesktop` builds scidesktop from this repository and
# passes it in as the `scidesktop` image below; nothing is pulled from a
# registry. A plain `docker build` of this folder fails, because no image called
# `scidesktop` exists outside bake.
#
# Add what microscopy needs on top of scidesktop here. The base is built as the
# notebook user; switch to root for system changes and back at the end:
#
#   USER root
#   COPY catalogues.json /etc/sciget/catalogues.json
#   USER ${NB_UID}
#
# Changes every image needs belong in the base (components/), not here; see
# docs/images.md.

FROM scidesktop

LABEL org.opencontainers.image.title="microdesktop" \
      org.opencontainers.image.description="scidesktop for microscopy"
