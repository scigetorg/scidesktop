# Viewers: FreeBrowse, Neuroglancer and NiiVue in JupyterLab

Volumetric image viewers are standalone components in `components/` built
outside `/opt/conda`:

| Component | Included in | What it is | Opens |
| --- | --- | --- | --- |
| `jupyterlab-freebrowse` | `neurodesktop` | [FreeBrowse](https://github.com/neurodesk/freebrowse), built from Neurodesk's fork at a pinned commit | `.nvd` NiiVue documents on double-click; `.nii` and `.nii.gz` through **Open With** or **Open in FreeBrowse** |
| `jupyterlab-neuroglancer` | `microdesktop` | [Google Neuroglancer](https://github.com/google/neuroglancer) standalone WebGL2 client at a pinned commit | **OME-Zarr** (Zarr v2 & v3), **N5**, and **Precomputed** folders via right-click → **Open in Neuroglancer** (or right-clicking `.zattrs`/`.zgroup`/`.zarray`/`zarr.json`/`attributes.json` → **Open Dataset in Neuroglancer**); `.ngstate` on double-click; `.nii`, `.nii.gz`, `.vtk`, `.obj`, `.swc` via **Open With**; blank viewer via the **Neuroglancer** launcher tile |
| `jupyterlab-niivue` | `neurodesktop` | [jupyterlab-niivue](https://github.com/niivue/niivue-vscode/tree/main/apps/jupyter), the NiiVue viewer: the wheel from PyPI, unmodified | `.nii` and `.nii.gz` on double-click |

## Using them

- On **`microdesktop`**, right-click any `.ome.zarr`, `.zarr`, `.n5`, or Precomputed dataset folder in JupyterLab's file browser and choose **Open in Neuroglancer**, or click the **Neuroglancer** launcher tile to inspect remote or local datasets. Neuroglancer uses `type: "auto"` so multi-channel OME-Zarr microscopy volumes (with OMERO metadata), segmentations, and meshes configure automatically.
- On **`neurodesktop`**, double-click a `.nii` or `.nii.gz` file in JupyterLab's file browser to open it in NiiVue, or right-click and choose **Open in FreeBrowse**.

All viewers draw in the browser with WebGL2 and keep local data behind the
notebook server's login (`/files/`).

## How they are installed

A JupyterLab extension normally lives in the Jupyter environment
(`/opt/conda`), which every image shares. These are optional, so each
component installs outside it:

| Part | Where | How JupyterLab finds it |
| --- | --- | --- |
| the JupyterLab extension | `/opt/<component>/lib/share/jupyter/labextensions/...` | a link in `/usr/local/share/jupyter/labextensions/`, where JupyterLab looks without being told |
| the server extension (a Python package) | `/opt/<component>/lib/` | the component's `/etc/scidesktop/jupyter_server_config.d/<component>.py` adds the folder to the server's import path and switches the extension on |

Kernels and terminals do not get that import path. Nothing listens on a
port: the server extensions are handlers of the notebook server.

- **NiiVue** serves its own JavaScript at
  `<session URL>/lab/extensions/@niivue/jupyter/static/`. Upstream serves
  those packaged files without a login. They are the code anyone can
  download from PyPI, never a user's file.
- **FreeBrowse** is an application in a frame at `<session URL>/freebrowse/`,
  behind the notebook server's login. It serves only its packaged files.
- **Neuroglancer** is an application in a frame at `<session URL>/neuroglancer/`,
  behind the notebook server's login. It serves only its packaged files and
  loads local OME-Zarr / N5 / Precomputed / NIfTI / mesh datasets from
  same-origin `<session URL>/files/`.

**One default viewer.** FreeBrowse registers itself as the default for NIfTI
files and so does NiiVue. The FreeBrowse build changes its registration to
`.nvd` only, as neurodesktop does, so the two never compete. The build stops
if upstream moves that line.

## Updating

| What | Where | How |
| --- | --- | --- |
| jupyterlab-niivue | `JUPYTERLAB_NIIVUE_VERSION` in `docker-bake.hcl` | Renovate proposes the version. Update `JUPYTERLAB_NIIVUE_SHA256` from the wheel's SHA-256 on PyPI |
| FreeBrowse | `FREEBROWSE_COMMIT` in `docker-bake.hcl` | Renovate proposes the fork's new commits |
| Neuroglancer | `NEUROGLANCER_COMMIT` in `docker-bake.hcl` | Renovate tracks `google/neuroglancer` `master` |
| Node.js for the viewer builds | `NODE_VERSION` (shared with `acp-adapters`) | Renovate |

FreeBrowse and Neuroglancer are built against the JupyterLab in
`components/jupyter-env`, so a JupyterLab update rebuilds them. `npm ci`
installs exact lock files for Neuroglancer and its JupyterLab extension.

## Checks

```sh
docker buildx bake jupyterlab-niivue-test jupyterlab-freebrowse-test jupyterlab-neuroglancer-test
./test/jupyterlab-niivue-smoke.sh neurodesktop
./test/jupyterlab-freebrowse-smoke.sh neurodesktop
./test/jupyterlab-neuroglancer-smoke.sh microdesktop
```

The checks cover what JupyterLab needs to open a file or OME-Zarr store: the
extension is offered to the page, its code and application assets are served,
and a NIfTI file (plus an OME-Zarr v0.4 store with `.zattrs`/`.zgroup`/`.zarray`
dotfiles for Neuroglancer) comes back unchanged behind the login. End-to-end
WebGL2 rendering is verified in headless Chrome by `./test/browser-smoke.sh`.

## Licences

| What | Licence | In the image |
| --- | --- | --- |
| jupyterlab-niivue | BSD-2-Clause | `/opt/jupyterlab-niivue/lib/jupyterlab_niivue-*.dist-info/licenses/LICENSE` |
| FreeBrowse | BSD-2-Clause (Martinos Center, MGH); its Jupyter extension declares MIT | `/opt/jupyterlab-freebrowse/LICENSE` |
| Neuroglancer | Apache-2.0 (Google LLC) | `/opt/jupyterlab-neuroglancer/LICENSE` |
