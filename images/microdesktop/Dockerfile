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
#   sciget-microscopy        narrows sciget to the microscopy catalog only
#   jupyterlab-neuroglancer  Neuroglancer WebGL2 viewer for OME-Zarr, N5, Precomputed and microscopy volumes
#
# Slurm (+ jupyterlab-slurm), VS Code (+ core extensions), DataLad,
# workflow engines (Nextflow, nf-test, Snakemake), VirtualGL, scigethelpers,
# FreeBrowse viewer, coding agents, ACP adapters, T3 Code and T3 Connect are
# inherited from scidesktop.

FROM scidesktop-base

COPY --link --from=sciget-microscopy / /
COPY --link --from=jupyterlab-neuroglancer / /

LABEL org.opencontainers.image.title="microdesktop" \
      org.opencontainers.image.description="scidesktop for microscopy: the microscopy tools through sciget"
