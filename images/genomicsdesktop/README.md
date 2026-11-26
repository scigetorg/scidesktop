# genomicsdesktop

`scidesktop` for genomics and single-cell bioinformatics: builds on
`scidesktop`'s shared workflow engines (**Nextflow**, **nf-test**, **Viash**,
**Snakemake**, and `/etc/scidesktop/nextflow/scidesktop.config` for rootless
Apptainer and session Slurm execution), narrows sciget to `sciget-datascience`
until a dedicated `genomics` catalog is published in `scigetorg/apps-catalog`,
adds the curated **Viash Hub & OpenPipelines** catalog (`viash-hub` /
`viash-catalog`), ships a locked Python 3.13 **Genomics** Jupyter kernel
(`/opt/genomics-env`) with `anndata`, `scanpy`, `mudata`, `biopython`,
`polars`, `pyarrow`, `h5py`, `zarr`, `dask`, `xarray`, `scikit-learn`,
`statsmodels`, `igraph`, `leidenalg`, `umap-learn`, `pyyaml`, `jsonschema`,
and `nf-core`, and configures coding-agent instructions (`genomics-agents`) for
Viash, OpenPipelines, and EESSI genomics modules (`SAMtools`, `BCFtools`,
`BEDTools`, `BWA`, `Bowtie2`, `minimap2`, `STAR`, `Salmon`, `FastQC`,
`MultiQC`, `GATK`, `R-bundle-Bioconductor`, and more).

| Component | What it adds |
| --- | --- |
| `sciget-datascience` | narrows sciget to the `datascience` catalog (RStudio, IRkernel, Nextflow, DataLad, rclone, Globus) |
| `viash-hub` | curated Viash Hub & OpenPipelines catalog (`/etc/scidesktop/viash-hub/catalog.json`) and `viash-catalog` CLI (`list`, `info`, `run-cmd`, `init`, `json`) |
| `genomics-env` | locked Python 3.13 genomics & single-cell kernel (`/opt/genomics-env`) and EESSI genomics catalog/launchers |
| `genomics-agents` | coding-agent instructions (`/opt/genomics-agents/AGENTS.md`) for Codex, Claude Code, OpenCode and T3 Code |

```sh
docker buildx bake genomicsdesktop
./test/image-smoke.sh genomicsdesktop
```
