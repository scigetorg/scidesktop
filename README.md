# scidesktop

A browser-accessible Linux desktop and JupyterLab in one container.

The desktop is streamed by [Selkies](https://github.com/selkies-project/selkies): the web
interface, signalling, video, audio and input all share a single TCP port, which
jupyter-server-proxy already serves. There is no TURN server, no relay port range and no
second listener, so the container deploys behind a JupyterHub ingress with nothing exposed
but Jupyter itself.

> **Status: experimental.** Not yet published, and the interfaces below may change.

## Running it

The image is assembled from components under `components/` with `docker buildx bake`
(see [docs/components.md](docs/components.md)), for amd64 and arm64. A local build is for
the machine it runs on.

```sh
docker buildx bake                           # builds every image (scidesktop:latest, ...)
docker buildx bake test                      # every component's own test
docker run --rm -p 8888:8888 --shm-size=2g -e JUPYTER_TOKEN=scidesktop \
    --cap-drop ALL --security-opt no-new-privileges:true \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined scidesktop
./test/image-smoke.sh scidesktop             # end-to-end checks
```

The two `--security-opt` flags let Apptainer run containers inside it; see
[Platform requirements](docs/operator-runbook.md#platform-requirements).
sciget is built from a pinned commit; to build your own working copy instead,
use `SCIGET_SRC=../sciget docker buildx bake --allow=fs.read=..`.

Open <http://localhost:8888/lab?token=scidesktop> and choose **Desktop** from the launcher.
The desktop session starts on first use, so a session that only ever uses notebooks never
pays for it.

**Tools** come from sciget's catalogs. `scidesktop` ships all sciget domains
(`neuroimaging`, `microscopy`, `datascience`, `dermatology`, `preclinical` and `molecular-imaging`) out of the box; domain images narrow the
offered catalog to their own community (and users can add more with
`sciget catalog add <name> <url>`).

**Applications** start from launcher tiles: each desktop entry in `SCIDESKTOP_APP_DIRS`
(default `/opt/sciget/applications`, where sciget writes its launchers) becomes a tile
(grouped by its desktop category, or *Desktop applications* by default), which
starts the application maximised on the desktop and opens the stream. The desktop's
taskbar switches between open applications and has three buttons: sciget's text
interface for browsing and launching containers, the Thunar file manager and a terminal.

**Your own Python environments** live in your home and become notebook kernels the
standard Jupyter way:

```sh
mamba create -p ~/envs/analysis python ipykernel numpy
~/envs/analysis/bin/python -m ipykernel install --user --name analysis
```

`--shm-size` matters: the X server uses shared memory, and Docker's 64 MB default is not
enough for a large virtual screen.

## Images

| Image | Folder | What it adds |
|---|---|---|
| scidesktop | [images/scidesktop](images/scidesktop) | The base: everything below, including all sciget domains (`sciget-all`), Slurm + `jupyterlab-slurm`, VS Code (`code-server`, `vscode-core`), DataLad, workflow engines (Nextflow, nf-test, Viash, Snakemake + shared Apptainer/Slurm Nextflow profiles), Lightcone (`lc`, with a compute catalog sized to the Slurm queue), VirtualGL, `scigethelpers`, and the [coding agents, Jupyter AI ACP adapters, T3 Code and T3 Connect](docs/coding-agents.md) |
| microdesktop | [images/microdesktop](images/microdesktop) | Microscopy: narrows sciget to the microscopy tools (`sciget-microscopy`) and adds [Neuroglancer](docs/viewers.md) (`jupyterlab-neuroglancer`) plus the locked `microscopy` Python kernel (`microscopy-env`: `scikit-image`, `tifffile`, `zarr`, `ome-zarr`, `bioio`, `dask`, `xarray`); inherits every generic feature from `scidesktop` |
| datadesktop | [images/datadesktop](images/datadesktop) | Data Science: narrows sciget to the datascience catalog (`sciget-datascience`) and adds the locked `datascience` Python kernel (`datascience-env`: `polars`, `pyarrow`, `duckdb`, `jupysql`, `scikit-learn`, `statsmodels`, `xgboost`, `lightgbm`, `optuna`, `shap`, `plotly`, `altair`, `sqlalchemy`) and the [AI Ready workshop](docs/ai-ready.md) (`ai-ready`: its notebooks and kernel, Airflow, MLflow and PostgreSQL) |
| dermdesktop | [images/dermdesktop](images/dermdesktop) | Dermatology: narrows sciget to the dermatology catalog (`sciget-dermatology`) and adds [Neuroglancer](docs/viewers.md) (`jupyterlab-neuroglancer`) plus the locked `dermatology` Python kernel (`dermatology-env`: `scikit-image`, `tifffile`, `zarr`, `ome-zarr`, `bioio`, `openslide`, `pydicom`, `colour-science`, `trimesh`, `statsmodels`, `dask`, `xarray`) |
| preclinicaldesktop | [images/preclinicaldesktop](images/preclinicaldesktop) | Preclinical imaging: narrows sciget to the preclinical catalog (`sciget-preclinical`) and adds [NiiVue](docs/viewers.md) (`jupyterlab-niivue`, `vscode-niivue`) plus the locked `preclinical` Python kernel (`preclinical-env`: `nibabel`, `nilearn`, `SimpleITK`, `pydicom`, `brkraw`, `ipyniivue`, `scikit-image`, `tifffile`, `zarr`, `dask`, `xarray`) |
| moleculardesktop | [images/moleculardesktop](images/moleculardesktop) | Molecular imaging: narrows sciget to the molecular-imaging catalog (`sciget-molecular-imaging`) and adds [NiiVue](docs/viewers.md) (`jupyterlab-niivue`, `vscode-niivue`) plus the locked `molecular-imaging` Python kernel (`molecular-imaging-env`: `nibabel`, `nilearn`, `SimpleITK`, `pydicom`, `highdicom`, `ipyniivue`, `scikit-image`, `scikit-learn`, `statsmodels`) |
| genomicsdesktop | [images/genomicsdesktop](images/genomicsdesktop) | Genomics & single-cell: narrows sciget to the genomics catalog (`sciget-genomics`), adds the curated Viash Hub & OpenPipelines catalog (`viash-hub` / `viash-catalog`), coding-agent instructions (`genomics-agents`), EESSI genomics metadata/launchers, and the locked `genomics` Python kernel (`genomics-env`: `anndata`, `scanpy`, `mudata`, `biopython`, `polars`, `pyarrow`, `h5py`, `zarr`, `dask`, `xarray`, `igraph`, `leidenalg`, `umap-learn`, `pyyaml`, `jsonschema`, `nf-core`) |
| neurodesktop | [images/neurodesktop](images/neurodesktop) | [Neuroimaging](docs/neurodesktop.md): narrows sciget to neuroimaging, and adds the Neurodesk CVMFS config, [NiiVue](docs/viewers.md) (`jupyterlab-niivue`, `vscode-niivue`), [FreeBrowse](docs/viewers.md) (`jupyterlab-freebrowse`), the neuroimaging Python kernel (`neuroimaging-env`), the Neurodesk compatibility layer (`neurodesk-compat`), Claude Code/Codex VS Code extensions (`vscode-coding-agents`) and Neurodesk's coding-agent defaults |

Domain images build `FROM scidesktop` and add only their own files, like the
[docker-stacks](https://github.com/jupyter/docker-stacks) images. Bake builds the
base alongside them, so nothing needs publishing first. To start a new one, or
to build one for your own community in a fork, see [docs/images.md](docs/images.md).

CI builds and tests every image on amd64 and arm64. On `main` it publishes
scidesktop, microdesktop, datadesktop, dermdesktop, preclinicaldesktop, moleculardesktop, genomicsdesktop and neurodesktop as multi-arch images tagged with the commit's short SHA, the UTC date and `latest`. Users can pull every published image from either registry:

- **GHCR** (primary, with build provenance attestations): `ghcr.io/scigetorg/<image>:<tag>`
- **Quay.io** (mirror): `quay.io/scigetorg/<image>:<tag>`

See [docs/images.md](docs/images.md#mirroring-to-quayio) for publishing and mirror details.

## What is in it

| | |
|---|---|
| Base | Ubuntu 26.04 LTS, digest-pinned, packages from a dated `snapshot.ubuntu.com` snapshot |
| Startup | docker-stacks `start.sh` and hooks (hardened to drop privileges via `setpriv --no-new-privs` without `sudo`; JupyterHub contract) |
| Jupyter | JupyterLab and `jupyterhub-singleuser` in `/opt/conda` (micromamba, locked), with `bash_kernel`, `jupyter-resource-usage`, `jupyterlab_rise`, `jupyter-scheduler`, `nbgitpuller`, `papermill`, `pytest`, `anywidget`, `ipycanvas` and `uv` |
| Desktop | IceWM on Xvfb with Thunar and xfce4-terminal, PipeWire for audio, VirtualGL (`vglrun`) and `mesa-utils` |
| Streaming | Selkies from PyPI, in its own locked environment at `/opt/selkies` |
| Containers | Apptainer built from source; sciget with all domain catalogs (`sciget-all`) by default |
| Modules & EESSI | Lmod built from the upstream release; [EESSI](https://www.eessi.io/) CVMFS repository (`eessi-cvmfs`, `software.eessi.io`) wired into Lmod (`module load EESSI/2025.06`), `eessi-catalog` (syncing live curated `<domain>/eessi.json` catalogs from `apps-catalog` with built-in offline fallback), `eessi-launch`, and dedicated **EESSI** JupyterLab desktop launcher tiles (base `ParaView`, `Octave`, `Julia`, `R` plus domain launchers such as `napari` on `microdesktop` and `dermdesktop`, `R + CRAN` on `datadesktop`, `R + Bioconductor` on `neurodesktop`) when mounted |
| Viewers | [Neuroglancer](docs/viewers.md) on `microdesktop` and `dermdesktop`; [NiiVue](docs/viewers.md) on `neurodesktop`, `preclinicaldesktop` and `moleculardesktop`; [FreeBrowse](docs/viewers.md) on `neurodesktop` |
| Coding agents | Codex, Claude Code and OpenCode for terminals: upstream release binaries, checksummed, at `/opt/coding-agents` |
| AI chat | [Jupyter AI](docs/jupyter-ai.md) in JupyterLab with OpenCode, Codex and Claude personas (`acp-adapters`). No model, key or endpoint comes with it |
| T3 Code | The T3 Code server behind the notebook server's login, opened from the **scigent.ai** launcher tile; at `/opt/t3-code`, with Google Antigravity ACP (`antigravity-acp`) at `/opt/antigravity-acp` for Gemini models |
| T3 Connect | [Remote access](docs/t3-connect.md) to T3 Code from the T3 apps, through T3's relay. Off until the user sets it up; at `/opt/t3-connect` |
| Batch jobs | A [Slurm queue](docs/slurm.md) for the session (`sbatch`, `srun`) plus the `jupyterlab-slurm` Queue Manager extension in JupyterLab; [Lightcone](docs/slurm.md#lightcone)'s `lc` (lightcone-cli, `astra-tools`, `astra-spec`) at `/opt/lightcone`, launching on that queue with a catalog sized to it |
| VS Code | [code-server](docs/neurodesktop.md#vs-code) behind the notebook server's login, opened from the **VS Code** launcher tile, with `vscode-core` preinstalled (plus `vscode-niivue` and `vscode-coding-agents` on `neurodesktop`) |
| Data & workflows | DataLad (`datalad-container`, `datalad-osf`, `osf`) and git-annex at `/opt/datalad`; Nextflow, nf-test, Viash and Snakemake (+ Slurm executor plugin and `/etc/scidesktop/nextflow/scidesktop.config` Apptainer/Slurm profiles) at `/opt/workflow-engines`; `rclone`, `sshfs`, `davfs2`, `s3fs`, `rsync`, `aria2`, `gh` |
| Helper CLI | The `scigethelpers` command (`cite`, `kernel`, `check`, `info`, `uv`) at `/opt/scigethelpers-cli` |

The domain images add domain-specific components the base leaves out (and narrow
the sciget catalog to their domain; [which image has which](docs/images.md)):

| | |
|---|---|
| Domain catalogs | Narrow sciget to one domain: `sciget-neuroimaging`, `sciget-microscopy`, `sciget-datascience`, `sciget-dermatology`, `sciget-preclinical`, `sciget-molecular-imaging` or `sciget-genomics` ([docs/images.md](docs/images.md#tool-catalogs)) |
| Microscopy Python | The `microscopy` Jupyter kernel (`scikit-image`, `tifffile`, `imagecodecs`, `zarr`, `ome-zarr`, `bioio`, `dask`, `xarray`) at `/opt/microscopy-env` |
| Data Science Python | The `datascience` Jupyter kernel (`polars`, `pyarrow`, `duckdb`, `jupysql`, `scikit-learn`, `statsmodels`, `xgboost`, `lightgbm`, `optuna`, `shap`, `plotly`, `altair`, `sqlalchemy`) at `/opt/datascience-env` |
| Dermatology Python | The `dermatology` Jupyter kernel (`scikit-image`, `tifffile`, `imagecodecs`, `zarr`, `ome-zarr`, `bioio`, `openslide`, `pydicom`, `colour-science`, `trimesh`, `statsmodels`, `dask`, `xarray`) at `/opt/dermatology-env` |
| Preclinical Python | The `preclinical` Jupyter kernel (`nibabel`, `nilearn`, `SimpleITK`, `pydicom`, `brkraw`, `ipyniivue`, `scikit-image`, `tifffile`, `zarr`, `dask`, `xarray`) at `/opt/preclinical-env` |
| Molecular Imaging Python | The `molecular-imaging` Jupyter kernel (`nibabel`, `nilearn`, `SimpleITK`, `pydicom`, `highdicom`, `ipyniivue`, `scikit-image`, `scikit-learn`, `statsmodels`) at `/opt/molecular-imaging-env` |
| Genomics & Viash Hub | The `genomics` Jupyter kernel (`anndata`, `scanpy`, `mudata`, `biopython`, `polars`, `pyarrow`, `h5py`, `zarr`, `dask`, `xarray`, `igraph`, `leidenalg`, `umap-learn`, `pyyaml`, `jsonschema`, `nf-core`) at `/opt/genomics-env`, the curated Viash Hub & OpenPipelines catalog (`viash-hub` / `viash-catalog`), and genomics coding-agent instructions (`genomics-agents`) |
| Neuroimaging Python | The `neuroimaging` Jupyter kernel (`nibabel`, `nipype`, `niwrap`, `pydra`, `nipoppy`, `ipyniivue`, `datalad`, `xnat`, `nf-core`) at `/opt/neuroimaging-env` |
| Neurodesk | The Neurodesk CVMFS repository's mirrors and key (`neurodesk-cvmfs`), Neurodesk's coding-agent defaults (`neurodesk-agents`), Claude Code/Codex VS Code extensions (`vscode-coding-agents`), and FreeSurfer/nf-neuro compatibility (`neurodesk-compat`) |
| AI Ready | A Python 3.12 kernel with the workshop's libraries and MLflow, Airflow in its own environment, PostgreSQL from conda-forge; all locked, at `/opt/ai-ready` |

`/opt/scidesktop/manifest.d/` holds one JSON file per component with its versions. Design and rationale:
[docs/base-image.md](docs/base-image.md). **Contributing:** read [docs/components.md](docs/components.md)
first; CI enforces its rules.

Every external dependency is pinned by version or digest and checksummed where the
publisher provides one. Renovate proposes updates rather than builds drifting silently.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `DISPLAY` | `:20` | X display for the desktop session |
| `SCIDESKTOP_XVFB_SCREEN` | `8192x4096x24` | Virtual screen; oversized to allow client-driven resize |
| `SCIDESKTOP_APP_DIRS` | `/opt/sciget/applications` | Colon-separated folders whose desktop entries become launcher tiles; read when Jupyter starts |
| `SELKIES_BASIC_AUTH_PASSWORD` | generated | Desktop credential; generated per container if unset |
| `SCIDESKTOP_CVMFS_MODE` | `external` | `external`, `internal` or `disabled`; see the runbook |
| `SCIDESKTOP_APPTAINER_SETUID` | unused | Removed: Apptainer is built `--without-suid` and `starter-suid` is not shipped |
| `SCIDESKTOP_SCIGET_REFRESH` | `yes` | Download the sciget catalogs in the background at start |
| `SCIDESKTOP_EESSI_CATALOG_REFRESH` | `yes` | Sync curated `<domain>/eessi.json` launchers when EESSI CVMFS is mounted (fail-soft to built-in fallbacks) |
| `SCIDESKTOP_SLURM` | `yes` | Start the session's Slurm queue; see [docs/slurm.md](docs/slurm.md) |
| `AI_READY_PUBLIC_ORIGIN` | `http://127.0.0.1:8888` | AI images only: the origin users reach the session at; see [docs/ai-ready.md](docs/ai-ready.md) |
| `T3_CODE_WORKDIR` | the home folder | Images with T3 Code: the folder it starts in; see [docs/coding-agents.md](docs/coding-agents.md) |
| `CODE_SERVER_WORKDIR` | the home folder | Images with code-server: the folder VS Code opens |
| `NEURODESK_API_KEY` | unset | neurodesktop: the key for the Neurodesk model provider; see [docs/neurodesktop.md](docs/neurodesktop.md#coding-agents) |

## Operations

See the [operator runbook](docs/operator-runbook.md) for JupyterHub deployment,
the CVMFS and Apptainer environment contract, resource sizing and triage.

## Licence

See [LICENSE](LICENSE).
