# microdesktop

scidesktop for microscopy: the same JupyterLab, desktop, Apptainer, Lmod and
sciget, offering the microscopy tools and no others.

- **Tools.** `sciget find` lists the `microscopy` catalog; `sciget install
  <tool>/<version>` downloads a tool's container and writes its module; the
  sciget button on the desktop's taskbar browses and launches them. See
  [Tool catalogs](../../docs/images.md#tool-catalogs).
- **Viewers.** NIfTI files open in the NiiVue viewer from JupyterLab's file
  browser, or in FreeBrowse through **Open With**. See
  [docs/viewers.md](../../docs/viewers.md).
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

Only the assembly: this image is scidesktop plus components from
`components/`. Any other image can copy the same ones.

| Component | What it adds |
| --- | --- |
| `sciget-microscopy` | the microscopy catalog for sciget |
| `jupyterlab-niivue`, `jupyterlab-freebrowse` | the NiiVue and FreeBrowse viewers for NIfTI files |
| `coding-agents`, `t3-code` | Codex, Claude Code, OpenCode and the **scigent.ai** tile |

The microscopy tools are whatever the catalog publishes; none is listed in
this repository. See [docs/images.md](../../docs/images.md) for what an image
may change and how base changes are contributed.
