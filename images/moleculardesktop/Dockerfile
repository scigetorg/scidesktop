# syntax=docker/dockerfile:1
# moleculardesktop: scidesktop for molecular imaging research.
#
# `docker buildx bake moleculardesktop` builds scidesktop and the components
# below from this repository and passes them in under these names; nothing is
# pulled from a registry. A plain `docker build` of this folder fails, because
# no image of those names exists outside bake.
#
# This file only assembles. Each component brings its own files, hooks,
# launcher tiles and checks; changes to them belong in components/, where
# other images can copy them too (docs/images.md).
#
#   sciget-molecular-imaging  narrows sciget to the molecular-imaging catalog only
#   vscode-niivue             NiiVue VS Code extension for NIfTI and medical images
#   jupyterlab-niivue         NiiVue JupyterLab viewer (default for NIfTI files)
#   molecular-imaging-env     locked Python 3.13 molecular imaging kernel (nibabel, nilearn, SimpleITK, pydicom, highdicom, ipyniivue, scikit-image, scikit-learn, statsmodels)
#
# Slurm (+ jupyterlab-slurm), VS Code (+ core extensions), DataLad,
# workflow engines (Nextflow, nf-test, Snakemake), VirtualGL, scigethelpers,
# coding agents, ACP adapters, T3 Code and T3 Connect are
# inherited from scidesktop.

FROM scidesktop-base

COPY --link --from=sciget-molecular-imaging / /
COPY --link --from=vscode-niivue / /
COPY --link --from=jupyterlab-niivue / /
COPY --link --from=molecular-imaging-env / /

ENV SCIDESKTOP_FLAVOUR=moleculardesktop

LABEL org.opencontainers.image.title="moleculardesktop" \
      org.opencontainers.image.description="scidesktop for molecular imaging: molecular-imaging sciget catalog, NiiVue viewers, and locked Python 3.13 PET, SPECT and quantitative imaging kernel"
