# Working in genomicsdesktop

This session is a `genomicsdesktop` container: JupyterLab, a Linux desktop,
workflow engines (Nextflow, nf-test, Viash, Snakemake), curated Viash Hub
workflows, EESSI bioinformatics modules, and a locked Python 3.13 genomics and
single-cell kernel. You run as the notebook user without root. The home folder
persists between sessions; `/tmp` does not.

## Running containerized workflows (rootless Apptainer, no Docker daemon)

There is no Docker daemon inside this session. Containers run via rootless
Apptainer (`apptainer` / `singularity`).

- Always pass the shared Nextflow config when running containerized Nextflow,
  OpenPipelines, Viash Hub, or nf-core pipelines:
  `-c /etc/scidesktop/nextflow/scidesktop.config -profile apptainer`
  (or `-profile apptainer,slurm` to schedule tasks on the session Slurm queue).
- Viash 0.9.x / OpenPipelines VDSL3 generated `main.nf` modules require
  `NXF_SYNTAX_PARSER=v1` on Nextflow 26+ (`viash-catalog run-cmd` includes this
  automatically). Do not set it globally for modern Nextflow v2 pipelines.
- `$NXF_APPTAINER_CACHEDIR` and `$NXF_SINGULARITY_CACHEDIR` default to
  `~/.cache/nextflow/{apptainer,singularity}` so pulled SIF images persist
  across sessions.
- Keep inputs and outputs under `$HOME` unless told otherwise so Apptainer
  auto-mounts expose them cleanly to containers.

## Discovering Viash Hub and OpenPipelines workflows

Use `viash-catalog` to inspect curated Viash Hub repositories and generate
pinned Nextflow commands:

- `viash-catalog list` (or `--domain genomics` / `--domain cellular-biology`)
  lists curated packages (`openpipelines`, `openpipelines-spatial`, `biobox`,
  `openproblems-batch-integration`).
- `viash-catalog json` outputs machine-readable catalog metadata.
- `viash-catalog info <id>` shows repository details, supported file formats
  (`.h5mu`, `.h5ad`, FASTQ/BAM/VCF), and available workflows.
- `viash-catalog run-cmd <id> [workflow] [--slurm]` prints the exact pinned
  `nextflow run ... -c /etc/scidesktop/nextflow/scidesktop.config -profile apptainer`
  command.
- Before launching a Viash or Nextflow pipeline, inspect its `config.vsh.yaml`
  or `nextflow_schema.json` (or run `--help`) to validate parameter names,
  types, and required inputs instead of guessing flags.

## Authoring reusable Viash components

Promote analysis scripts into reusable, unit-tested Viash components rather
than leaving one-off shell history behind:

- Scaffold a component with
  `viash-catalog init <name> [--lang python|bash|r] [--image <oci-image>]`.
- Pass `--image <oci-image>` to wrap an existing SCIGET/`neurocontainers` or
  OCI container image as a Viash `docker` engine for Nextflow VDSL3 export
  without duplicating container builds.
- Develop and unit-test locally using Viash's `native` engine (no Docker daemon
  required): `viash test config.vsh.yaml --engine native` and
  `viash run config.vsh.yaml -- --input ... --output ...`.
- Export a Nextflow VDSL3 module with
  `viash build config.vsh.yaml --runner nextflow --output target/nextflow`.
  Build custom Docker container images in CI (e.g. GitHub Actions).

## Genomics Python kernel, EESSI modules, and sciget tools

- The locked `Genomics (Python 3.13)` kernel lives at `/opt/genomics-env` and
  provides `anndata`, `scanpy`, `mudata` (for OpenPipelines `.h5mu`/`.h5ad`
  outputs), `biopython`, `polars`, `pyarrow`, `h5py`, `zarr`, `dask`, `xarray`,
  `scikit-learn`, `statsmodels`, `umap-learn`, `igraph`, `leidenalg`, `pyyaml`,
  `jsonschema`, and `nf-core`. Do not install packages into `/opt/conda` or
  `/opt/genomics-env`; create per-project environments under `~/envs/<name>`
  (`mamba create -p ~/envs/<name> ...` or `uv venv`).
- When `/cvmfs/software.eessi.io` is mounted, load pinned bioinformatics tools
  via Lmod in login shells (`bash -lc 'module load EESSI/2025.06 && module load SAMtools/1.22.1 ...'`).
  Run `eessi-catalog list` to see curated EESSI genomics tools (`SAMtools`,
  `BCFtools`, `BEDTools`, `BWA`, `Bowtie2`, `minimap2`, `STAR`, `Salmon`,
  `FastQC`, `MultiQC`, `fastp`, `GATK`, `VCFtools`, `BLAST+`, `HMMER`,
  `DIAMOND`, `MMseqs2`, `Flye`, `IQ-TREE`, `Kraken2`, `R-bundle-Bioconductor`).
- Use `sciget find <name>` and `sciget install <tool/version>` for container
  tools from configured sciget catalogs.

## Data hygiene and reproducibility

- Treat raw sequencing and single-cell inputs (FASTQ, BAM/CRAM, VCF, `.h5ad`,
  `.h5mu`) as read-only; write derived outputs to a dedicated results folder.
- Never put participant/patient identifiers, clinical metadata, API tokens, or
  passwords in prompts, commits, or logs.
- Use `scigethelpers cite` to generate `CITATIONS.md` for loaded modules, and
  record exact tool, pipeline, and Viash Hub revision tags for every run.
