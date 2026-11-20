# microdesktop

scidesktop for microscopy: the same JupyterLab, desktop, Apptainer, Lmod and
sciget, with microscopy applications on top. It also has the
[coding agents and T3 Code](../../docs/coding-agents.md): `codex`, `claude`
and `opencode` in terminals, and the **scigent.ai** launcher tile.

> **Status: shell.** Beyond the coding agents it is scidesktop with its own
> name, ready to be built out.

## Building and running

From the repository root:

```sh
docker buildx bake microdesktop       # builds scidesktop and the components, then microdesktop:latest
docker run --rm -p 8888:8888 --shm-size=2g -e JUPYTER_TOKEN=microdesktop \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined microdesktop
./test/image-smoke.sh microdesktop    # the base's end-to-end checks and the components'
```

Open <http://localhost:8888/lab?token=microdesktop>.

## Building it out

Everything specific to microdesktop lives in this folder: the `Dockerfile` and
any files it copies. The coding agents are the `coding-agents` and `t3-code`
components (`components/`), which aidesktop copies too; aimicrodesktop gets
them from this image. See [docs/images.md](../../docs/images.md) for what an image
may change and how base changes are contributed.
