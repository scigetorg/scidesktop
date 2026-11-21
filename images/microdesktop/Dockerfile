# syntax=docker/dockerfile:1
# microdesktop: scidesktop for microscopy.
#
# `docker buildx bake microdesktop` builds scidesktop and the components below
# from this repository and passes them in under these names; nothing is
# pulled from a registry. A plain `docker build` of this folder fails, because
# no image of those names exists outside bake.
#
# This file only assembles. Each component brings its own files, hooks,
# launcher tiles and checks; changes to them belong in components/, where
# other images can copy them too (docs/images.md).
#
#   sciget-microscopy  the microscopy catalog for sciget: the only tools offered
#   jupyterlab-niivue, jupyterlab-freebrowse  viewers for NIfTI files in JupyterLab
#   coding-agents      Codex, Claude Code and OpenCode (docs/coding-agents.md)
#   t3-code            the scigent.ai tile

FROM scidesktop-base

COPY --link --from=sciget-microscopy / /
COPY --link --from=jupyterlab-niivue / /
COPY --link --from=jupyterlab-freebrowse / /
COPY --link --from=coding-agents / /
COPY --link --from=t3-code / /
COPY --link --from=t3-connect / /

LABEL org.opencontainers.image.title="microdesktop" \
      org.opencontainers.image.description="scidesktop for microscopy: the microscopy tools through sciget"
