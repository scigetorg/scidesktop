# neurodesktop

scidesktop for neuroimaging: what
[neurodesk/neurodesktop](https://github.com/neurodesk/neurodesktop) gives its
users, built from scidesktop components. The Neurodesk tools (FSL, FreeSurfer,
ANTs, MRtrix3 and the rest) are containers, loaded as modules from the
Neurodesk CVMFS repository or installed with sciget. On top of the base it has
DataLad and git-annex, a VS Code tile, and the
[coding agents and T3 Code](../../docs/coding-agents.md) with Neurodesk's
instructions and model provider.

[docs/neurodesktop.md](../../docs/neurodesktop.md) says how to use and deploy
it, and lists what was ported from neurodesktop and what was not.

## Building and running

From the repository root:

```sh
docker buildx bake neurodesktop       # builds scidesktop and the components, then neurodesktop:latest
docker run --rm -p 8888:8888 --shm-size=2g -e JUPYTER_TOKEN=neurodesktop \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined neurodesktop
./test/image-smoke.sh neurodesktop    # the base's end-to-end checks and each component's
```

Open <http://localhost:8888/lab?token=neurodesktop>. Without CVMFS the tools
come from the registry: `sciget find fsl`, then `sciget install fsl/<version>`.

To mount the Neurodesk repository inside the container, so every tool is a
module at once:

```sh
docker run --rm -p 8888:8888 --shm-size=2g -e JUPYTER_TOKEN=neurodesktop \
    --user root --cap-add SYS_ADMIN --device /dev/fuse \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
    -e SCIDESKTOP_CVMFS_MODE=internal neurodesktop
```

Then, in a terminal: `module avail`, `module load niimath/<version>`, `niimath`.

## What is here

Only the assembly: this image is `scidesktop` (which already includes Slurm +
`jupyterlab-slurm`, VS Code with `vscode-core` and `vscode-niivue`, DataLad,
workflow engines, VirtualGL, `scigethelpers`, the NiiVue/FreeBrowse viewers,
coding agents, ACP adapters, T3 Code and T3 Connect) plus neuroimaging-specific
components from `components/`.

| Component | What it adds |
| --- | --- |
| `sciget-neuroimaging` | narrows sciget to the neuroimaging catalog |
| `neurodesk-cvmfs` | the Neurodesk CVMFS repository: its mirrors and public key |
| `vscode-coding-agents` | Claude Code and Codex VS Code extensions |
| `neurodesk-agents` | the agents' instructions for Neurodesk tools, and the Neurodesk model provider for OpenCode |
| `neuroimaging-env` | the `neuroimaging` Jupyter kernel (`nibabel`, `nipype`, `niwrap`, `pydra`, `nipoppy`, `ipyniivue`, `datalad`, `xnat`, `nf-core`) |
| `neurodesk-compat` | FreeSurfer/nf-neuro defaults, bundled `nf-neuro` modules, local module discovery and getting-started notebook |
