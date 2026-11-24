# microdesktop

scidesktop for microscopy: the same JupyterLab, desktop, Apptainer, Lmod and
sciget, narrowed to the microscopy catalog and paired with Neuroglancer and a
locked Python bioimaging kernel.

- **Tools.** `sciget find` lists the `microscopy` catalog; `sciget install
  <tool>/<version>` downloads a tool's container and writes its module; the
  sciget button on the desktop's taskbar browses and launches them. See
  [Tool catalogs](../../docs/images.md#tool-catalogs).
- **Viewers.** OME-Zarr, N5, Precomputed, NIfTI and mesh datasets open in
  Neuroglancer from JupyterLab's file browser or launcher tile. See
  [docs/viewers.md](../../docs/viewers.md).
- **Microscopy Python kernel.** The `Microscopy (Python 3.13)` kernel at
  `/opt/microscopy-env` provides `numpy`, `scipy`, `pandas`, `scikit-image`,
  `scikit-learn`, `matplotlib`, `seaborn`, `dask`, `xarray`, `imageio`,
  `tifffile`, `imagecodecs`, `zarr`, `ome-zarr`, `bioio` (`bioio-ome-tiff`,
  `bioio-ome-zarr`, `bioio-tifffile`) and `watermark`.
- **Coding agents.** `codex`, `claude` and `opencode` in terminals, and the
  **scigent.ai** launcher tile. See
  [docs/coding-agents.md](../../docs/coding-agents.md).

## Building and running

From the repository root:

```sh
docker buildx bake microdesktop       # builds scidesktop and the components, then microdesktop:latest
docker run --rm -p 8888:8888 --shm-size=2g -e JUPYTER_TOKEN=microdesktop \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined microdesktop
./test/image-smoke.sh microdesktop    # the base's end-to-end checks and each component's
```

Open <http://localhost:8888/lab?token=microdesktop>. In a terminal:
`sciget find`, then `sciget install nextpyp/<version>`.

## What is here

Only the assembly: this image is `scidesktop` (which already includes Slurm +
`jupyterlab-slurm`, VS Code with `vscode-core`, DataLad, workflow engines,
VirtualGL, `scigethelpers`, coding agents, ACP adapters, T3 Code and T3
Connect) plus the microscopy components:

| Component | What it adds |
| --- | --- |
| `sciget-microscopy` | narrows sciget to the microscopy catalog |
| `jupyterlab-neuroglancer` | Neuroglancer WebGL2 viewer for OME-Zarr, N5, Precomputed and microscopy volumes |
| `microscopy-env` | locked Python 3.13 microscopy kernel (`/opt/microscopy-env`) |

The microscopy tools are whatever the catalog publishes; none is listed in
this repository. See [docs/images.md](../../docs/images.md) for what an image
may change and how base changes are contributed.
