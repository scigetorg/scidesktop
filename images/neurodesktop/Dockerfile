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
#   sciget-neuroimaging  narrows sciget to the neuroimaging catalog only
#   neurodesk-cvmfs      the Neurodesk CVMFS repository: its mirrors and key
#   vscode-niivue        NiiVue VS Code extension for NIfTI and medical images
#   vscode-coding-agents Claude Code and Codex VS Code extensions
#   jupyterlab-niivue     NiiVue JupyterLab viewer (default for NIfTI files)
#   jupyterlab-freebrowse FreeBrowse JupyterLab viewer (.nvd and NIfTI via Open With)
#   neurodesk-agents      Neurodesk's instructions and model provider for the agents
#   neuroimaging-env      neuroimaging Python analysis kernel (nibabel, nipype, niwrap, pydra, nipoppy, ipyniivue, datalad, xnat, nf-core)
#   neurodesk-compat      FreeSurfer/nf-neuro defaults, local module discovery, getting-started notebook
#
# Slurm (+ jupyterlab-slurm), VS Code (+ core extensions), DataLad,
# workflow engines (Nextflow, nf-test, Snakemake), VirtualGL, scigethelpers,
# coding agents, ACP adapters, T3 Code and T3 Connect are
# inherited from scidesktop.

FROM scidesktop-base

COPY --link --from=sciget-neuroimaging / /
COPY --link --from=neurodesk-cvmfs / /
COPY --link --from=vscode-niivue / /
COPY --link --from=vscode-coding-agents / /
COPY --link --from=jupyterlab-niivue / /
COPY --link --from=jupyterlab-freebrowse / /
COPY --link --from=neurodesk-agents / /
COPY --link --from=neuroimaging-env / /
COPY --link --from=neurodesk-compat / /

LABEL org.opencontainers.image.title="neurodesktop" \
      org.opencontainers.image.description="scidesktop for neuroimaging: the Neurodesk tools as modules"
