# syntax=docker/dockerfile:1
# neurodesktop: scidesktop for neuroimaging. What neurodesk/neurodesktop gives
# its users, assembled from components (docs/neurodesktop.md).
#
# `docker buildx bake neurodesktop` builds scidesktop and the components below
# from this repository and passes them in under these names; nothing is
# pulled from a registry. A plain `docker build` of this folder fails, because
# no image of those names exists outside bake.
#
# This file only assembles. Each component brings its own files, hooks,
# launcher tiles, home defaults and checks; changes to them belong in
# components/, where other images can copy them too. Components are ordered
# from least to most frequently changed.
#
#   sciget-neuroimaging  the neuroimaging catalog for sciget, and its modules
#   neurodesk-cvmfs   the Neurodesk CVMFS repository: its mirrors and key
#   datalad           DataLad and git-annex
#   jupyterlab-niivue, jupyterlab-freebrowse  viewers for NIfTI files in JupyterLab
#   code-server       the VS Code tile
#   vscode-core, vscode-niivue, vscode-coding-agents  preinstalled VS Code extensions
#   coding-agents     Codex, Claude Code and OpenCode (docs/coding-agents.md)
#   t3-code           the scigent.ai tile
#   neurodesk-agents  Neurodesk's instructions and model provider for the agents
#   scigethelpers-cli the `scigethelpers` command (cite, kernel, check, info)

FROM scidesktop-base

COPY --link --from=sciget-neuroimaging / /
COPY --link --from=neurodesk-cvmfs / /
COPY --link --from=datalad / /
COPY --link --from=jupyterlab-niivue / /
COPY --link --from=jupyterlab-freebrowse / /
COPY --link --from=code-server / /
COPY --link --from=vscode-core / /
COPY --link --from=vscode-niivue / /
COPY --link --from=vscode-coding-agents / /
COPY --link --from=coding-agents / /
COPY --link --from=t3-code / /
COPY --link --from=t3-connect / /
COPY --link --from=neurodesk-agents / /
COPY --link --from=scigethelpers-cli / /

LABEL org.opencontainers.image.title="neurodesktop" \
      org.opencontainers.image.description="scidesktop for neuroimaging: the Neurodesk tools as modules"
