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
(see [docs/components.md](docs/components.md)).

```sh
docker buildx bake                           # builds scidesktop:latest
docker buildx bake test                      # every component's own test
docker run --rm -p 8888:8888 --shm-size=2g -e JUPYTER_TOKEN=scidesktop \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined scidesktop
./test/smoke.sh scidesktop                   # end-to-end checks
```

The two `--security-opt` flags let Apptainer run containers inside it; see
[Platform requirements](docs/operator-runbook.md#platform-requirements).
sciget is built from a pinned commit; to build your own working copy instead,
use `SCIGET_SRC=../sciget docker buildx bake --allow=fs.read=..`.

Open <http://localhost:8888/lab?token=scidesktop> and choose **Desktop** from the launcher.
The desktop session starts on first use, so a session that only ever uses notebooks never
pays for it.

**Applications** start from launcher tiles: each desktop entry in `/opt/sciget/applications`
(where sciget writes its launchers) becomes a tile under *Desktop applications*, which
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

## What is in it

| | |
|---|---|
| Base | Ubuntu 26.04 LTS, digest-pinned, packages from a dated `snapshot.ubuntu.com` snapshot |
| Startup | docker-stacks `start.sh` and hooks, vendored unchanged (JupyterHub contract) |
| Jupyter | JupyterLab and `jupyterhub-singleuser` in `/opt/conda` (micromamba, locked) |
| Desktop | IceWM on Xvfb with Thunar and xfce4-terminal, PipeWire for audio |
| Streaming | Selkies from PyPI, in its own locked environment at `/opt/selkies` |
| Containers | Apptainer built from source; sciget with a default catalogue |
| Modules | Lmod, built from the upstream release |

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
| `SCIDESKTOP_APPTAINER_SETUID` | `auto` | `auto`, `yes` or `no`; applies only when the container starts as root |
| `SCIDESKTOP_SCIGET_REFRESH` | `yes` | Download the sciget catalogues in the background on a user's first start |

## Operations

See the [operator runbook](docs/operator-runbook.md) for JupyterHub deployment,
the CVMFS and Apptainer environment contract, resource sizing and triage.

## Licence

See [LICENSE](LICENSE).
