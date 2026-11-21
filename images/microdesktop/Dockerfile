# syntax=docker/dockerfile:1
# microdesktop: scidesktop for microscopy.
#
# `docker buildx bake microdesktop` builds scidesktop and the components below
# from this repository and passes them in under these names; nothing is
# pulled from a registry. A plain `docker build` of this folder fails, because
# no image of those names exists outside bake.
#
# The coding agents and T3 Code are the coding-agents and t3-code components
# (docs/coding-agents.md), shared with aidesktop. Copying a component is all
# an image does for it.
#
# Add what microscopy needs on top of scidesktop here. The base is built as the
# notebook user; switch to root for system changes and back at the end:
#
#   USER root
#   RUN sciget catalog add --system microscopy https://example.org/apps.json
#   USER ${NB_UID}
#
# Changes every image needs belong in the base (components/), not here; see
# docs/images.md.

FROM scidesktop-base

COPY --link --from=coding-agents / /
COPY --link --from=t3-code / /

LABEL org.opencontainers.image.title="microdesktop" \
      org.opencontainers.image.description="scidesktop for microscopy"
