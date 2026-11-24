# syntax=docker/dockerfile:1
# dermdesktop: scidesktop for dermatology research.
#
# `docker buildx bake dermdesktop` builds scidesktop and the components below
# from this repository and passes them in under these names; nothing is
# pulled from a registry. A plain `docker build` of this folder fails, because
# no image of those names exists outside bake.
#
# This file only assembles. Each component brings its own files, hooks,
# launcher tiles and checks; changes to them belong in components/, where
# other images can copy them too (docs/images.md).
#
#   sciget-dermatology       narrows sciget to the dermatology catalog only
#   jupyterlab-neuroglancer  Neuroglancer WebGL2 viewer for OME-Zarr whole-slide dermatopathology images
#   dermatology-env          locked Python 3.13 dermatology kernel (scikit-image, tifffile, zarr, ome-zarr, bioio, openslide, pydicom, colour-science, trimesh, statsmodels, dask, xarray)
#
# Slurm (+ jupyterlab-slurm), VS Code (+ core extensions), DataLad,
# workflow engines (Nextflow, nf-test, Snakemake), VirtualGL, scigethelpers,
# coding agents, ACP adapters, T3 Code and T3 Connect are
# inherited from scidesktop.

FROM scidesktop-base

COPY --link --from=sciget-dermatology / /
COPY --link --from=jupyterlab-neuroglancer / /
COPY --link --from=dermatology-env / /

LABEL org.opencontainers.image.title="dermdesktop" \
      org.opencontainers.image.description="scidesktop for dermatology: dermatology sciget catalog, Neuroglancer WSI viewer, and locked Python 3.13 dermoscopy, dermatopathology and 3D skin imaging kernel"
