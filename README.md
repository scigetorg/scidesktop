# scidesktop

A browser-accessible Linux desktop and JupyterLab in one container.

The desktop is streamed by [Selkies](https://github.com/selkies-project/selkies): the web
interface, signalling, video, audio and input all share a single TCP port, which
jupyter-server-proxy already serves. There is no TURN server, no relay port range and no
second listener, so the container deploys behind a JupyterHub ingress with nothing exposed
but Jupyter itself.

> **Status: experimental.** Not yet published, and the interfaces below may change.

## Running it

```sh
docker build -t scidesktop .
docker run --rm -p 8888:8888 --shm-size=2g -e JUPYTER_TOKEN=scidesktop scidesktop
```

Open <http://localhost:8888/lab?token=scidesktop> and choose **Desktop** from the launcher.
The desktop session starts on first use, so a session that only ever uses notebooks never
pays for it.

`--shm-size` matters: the X server uses shared memory, and Docker's 64 MB default is not
enough for a large virtual screen.

## What is in it

| | |
|---|---|
| Base | `quay.io/jupyter/base-notebook`, digest-pinned |
| Desktop | LXQt on Xvfb, with PipeWire for audio |
| Streaming | Selkies, built from a pinned commit |
| Modules | Lmod, built from the upstream release |

Every external dependency is pinned by version or digest and checksummed where the
publisher provides one. Renovate proposes updates rather than builds drifting silently.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `DISPLAY` | `:20` | X display for the desktop session |
| `SCIDESKTOP_XVFB_SCREEN` | `8192x4096x24` | Virtual screen; oversized to allow client-driven resize |
| `SELKIES_BASIC_AUTH_PASSWORD` | generated | Desktop credential; generated per container if unset |

## Licence

See [LICENSE](LICENSE).
