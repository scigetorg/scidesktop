# syntax=docker/dockerfile:1
# genomicsdesktop: scidesktop for genomics and single-cell bioinformatics.
#
# `docker buildx bake genomicsdesktop` builds scidesktop and the components
# below from this repository and passes them in under these names; nothing is
# pulled from a registry. A plain `docker build` of this folder fails, because
# no image of those names exists outside bake.
#
# This file only assembles. Each component brings its own files, hooks,
# launcher tiles and checks; changes to them belong in components/, where
# other images can copy them too (docs/images.md).
#
#   sciget-datascience  narrows sciget to the live datascience catalog (RStudio,
#                       IRkernel, Nextflow, DataLad, rclone, Globus) until a
#                       dedicated genomics domain is published in apps-catalog
#   viash-hub           curated Viash Hub & OpenPipelines workflow catalog and
#                       the `viash-catalog` CLI (discovery, Nextflow/Apptainer
#                       commands, Viash component scaffolding & container bridge)
#   genomics-env        locked Python 3.13 genomics & single-cell kernel
#                       (anndata, scanpy, mudata, biopython, polars, pyarrow,
#                       h5py, zarr, dask, xarray, igraph, leidenalg, umap-learn,
#                       pyyaml, jsonschema, nf-core) + EESSI genomics metadata
#   genomics-agents     coding-agent instructions for Viash Hub, OpenPipelines,
#                       rootless Apptainer Nextflow profiles, and EESSI genomics
#
# Slurm (+ jupyterlab-slurm), VS Code (+ core extensions), DataLad,
# workflow engines (Nextflow, nf-test, Viash, Snakemake + scidesktop Nextflow
# Apptainer/Slurm profiles), VirtualGL, scigethelpers, coding agents, ACP
# adapters, T3 Code and T3 Connect are inherited from scidesktop.

FROM scidesktop-base

COPY --link --from=sciget-datascience / /
COPY --link --from=viash-hub / /
COPY --link --from=genomics-env / /
COPY --link --from=genomics-agents / /

LABEL org.opencontainers.image.title="genomicsdesktop" \
      org.opencontainers.image.description="scidesktop for genomics and single-cell bioinformatics: Viash Hub & OpenPipelines catalog, rootless Apptainer Nextflow profiles, EESSI genomics modules, agent instructions, and locked Python 3.13 genomics/single-cell kernel"
