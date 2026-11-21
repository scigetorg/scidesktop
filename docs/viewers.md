# Viewers: NiiVue and FreeBrowse in JupyterLab

`scidesktop` (and every image built on it) opens NIfTI images in JupyterLab
with two viewers. Each is a standalone component in `components/` built outside
`/opt/conda`. They are the viewers
[neurodesktop](https://github.com/neurodesk/neurodesktop) ships, set up the
same way.

| Component | What it is | Opens |
| --- | --- | --- |
| `jupyterlab-niivue` | [jupyterlab-niivue](https://github.com/niivue/niivue-vscode/tree/main/apps/jupyter), the NiiVue viewer: the wheel from PyPI, unmodified | `.nii` and `.nii.gz` on double-click |
| `jupyterlab-freebrowse` | [FreeBrowse](https://github.com/neurodesk/freebrowse), built from Neurodesk's fork at a pinned commit | `.nvd` NiiVue documents on double-click; `.nii` and `.nii.gz` through **Open With** or **Open in FreeBrowse** in the file browser's menu |

## Using them

Double-click a `.nii` or `.nii.gz` file in JupyterLab's file browser: it
opens in NiiVue. Right-click it and choose **Open in FreeBrowse** for the
other viewer. Both draw in the browser with WebGL. Neither sends the image
anywhere: JupyterLab downloads the file from the notebook server and hands it
to the viewer in the page.

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

**One default viewer.** FreeBrowse registers itself as the default for NIfTI
files and so does NiiVue. The FreeBrowse build changes its registration to
`.nvd` only, as neurodesktop does, so the two never compete. The build stops
if upstream moves that line.

## Updating

| What | Where | How |
| --- | --- | --- |
| jupyterlab-niivue | `JUPYTERLAB_NIIVUE_VERSION` in `docker-bake.hcl` | Renovate proposes the version. Update `JUPYTERLAB_NIIVUE_SHA256` from the wheel's SHA-256 on PyPI |
| FreeBrowse | `FREEBROWSE_COMMIT` in `docker-bake.hcl` | Renovate proposes the fork's new commits |
| Node.js for the FreeBrowse build | `NODE_VERSION` (shared with `acp-adapters`) | Renovate |

FreeBrowse is built against the JupyterLab in `components/jupyter-env`, so a
JupyterLab update rebuilds it. `npm ci` installs exactly the fork's lock
file. The JupyterLab extension's `yarn.lock` upstream is incomplete, so yarn
resolves the missing entries at build time; those build tools are not in the
image.

## Checks

```sh
docker buildx bake jupyterlab-niivue-test jupyterlab-freebrowse-test
./test/jupyterlab-niivue-smoke.sh scidesktop
./test/jupyterlab-freebrowse-smoke.sh scidesktop
```

The checks cover what JupyterLab needs to open a file: the extension is
offered to the page, its code and FreeBrowse's application are served, and a
NIfTI file saved in the home comes back unchanged, behind the login, from the
address the viewers download it from. They do not draw the image, which
needs a browser with WebGL, and say so (`NOT TESTED`).

## Licences

| What | Licence | In the image |
| --- | --- | --- |
| jupyterlab-niivue | BSD-2-Clause | `/opt/jupyterlab-niivue/lib/jupyterlab_niivue-*.dist-info/licenses/LICENSE` |
| FreeBrowse | BSD-2-Clause (Martinos Center, MGH); its Jupyter extension declares MIT | `/opt/jupyterlab-freebrowse/LICENSE` |
