# syntax=docker/dockerfile:1
# preclinicaldesktop: scidesktop for preclinical imaging research.
#
# `docker buildx bake preclinicaldesktop` builds scidesktop and the components
# below from this repository and passes them in under these names; nothing is
# pulled from a registry. A plain `docker build` of this folder fails, because
# no image of those names exists outside bake.
#
# This file only assembles. Each component brings its own files, hooks,
# launcher tiles and checks; changes to them belong in components/, where
# other images can copy them too (docs/images.md).
#
#   sciget-preclinical  narrows sciget to the preclinical catalog only
#   vscode-niivue       NiiVue VS Code extension for NIfTI and medical images
#   jupyterlab-niivue   NiiVue JupyterLab viewer (default for NIfTI files)
#   preclinical-env     locked Python 3.13 preclinical imaging kernel (nibabel, nilearn, SimpleITK, pydicom, brkraw, ipyniivue, scikit-image, tifffile, zarr, dask, xarray)
#
# Slurm (+ jupyterlab-slurm), VS Code (+ core extensions), DataLad,
# workflow engines (Nextflow, nf-test, Snakemake), VirtualGL, scigethelpers,
# coding agents, ACP adapters, T3 Code and T3 Connect are
# inherited from scidesktop.

FROM scidesktop-base

COPY --link --from=sciget-preclinical / /
COPY --link --from=vscode-niivue / /
COPY --link --from=jupyterlab-niivue / /
COPY --link --from=preclinical-env / /

LABEL org.opencontainers.image.title="preclinicaldesktop" \
      org.opencontainers.image.description="scidesktop for preclinical imaging: preclinical sciget catalog, NiiVue viewers, and locked Python 3.13 small-animal MRI, CT and PET/SPECT kernel"
