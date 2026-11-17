# microdesktop

scidesktop for microscopy: the same JupyterLab, desktop, Apptainer, Lmod and
sciget, with microscopy applications on top.

> **Status: shell.** It is scidesktop with its own name, ready to be built out.

## Building and running

From the repository root:

```sh
docker buildx bake microdesktop       # builds scidesktop, then microdesktop:latest
docker run --rm -p 8888:8888 --shm-size=2g -e JUPYTER_TOKEN=microdesktop \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined microdesktop
./test/smoke.sh microdesktop          # the base's end-to-end checks
```

Open <http://localhost:8888/lab?token=microdesktop>.

## Building it out

Everything specific to microdesktop lives in this folder: the `Dockerfile` and
any files it copies. See [docs/images.md](../../docs/images.md) for what an image
may change and how base changes are contributed.
