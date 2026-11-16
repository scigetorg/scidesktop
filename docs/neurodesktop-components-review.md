# neurodesktop components: what belongs in the scidesktop base

Scan of `neurodesk/neurodesktop` at `5a9be54` (Dockerfile, 1873 lines, and
`config/`), 2026-11-15. The question for each component: is it generic to any
scientific desktop (neuroimaging, microscopy, ...) and cheap enough to carry in
the base, or does it belong in a derived image?

scidesktop today ships a deliberately small set: the LXQt desktop, audio,
Apptainer, CVMFS, Lmod, sciget, and a Jupyter environment of JupyterLab,
jupyterhub-singleuser, jupyter-server-proxy, ipykernel and mamba. It has no
git, no editor, no browser and no archive tools.

## A. In the base: only what cannot be a container

Rule (2026-11-16): the base carries a component only if at least one holds:

1. it is on the startup path;
2. another base component calls it;
3. it hooks into the system or the Jupyter server (extension, service, mount,
   interposer);
4. running it through Apptainer breaks it.

Everything else is delivered as a container through sciget (section B), even
when it is small.

| Component | Stays because | Rule |
| --- | --- | --- |
| ~~`nb_conda_kernels`~~ | **Dropped 2026-11-16:** it calls `conda`, which the mamba-only environment does not ship (tested: finds no environments, and fails on `mamba info`). Users register environments with `python -m ipykernel install --user` (README) | n/a |
| `jupyterlmod` | JupyterLab and server extension for the base's Lmod (PyPI only: a hashed pip lock in `jupyter-env`) | 3 |
| `jupyterlab-git` | JupyterLab and server extension | 3 |
| `git`, with `openssh-client` and `nano` | called by `jupyterlab-git`; git needs ssh for remotes and an editor for commit messages (`less`, its pager, is already in the base) | 2 |
| `ipywidgets` | a kernel-side package and JupyterLab extension | 3 |
| `jupyter-resource-usage` | server extension (scidesktop currently sets `JUPYTER_DISABLE_RESOURCE_USAGE=1`; decide deliberately) | 3 |
| `xz-utils` | `tar -J` calls the `xz` binary | 2 |
| `tmux` (or `screen`) | a containerised session manager would start every shell inside its own container image, not the desktop's environment | 4 |
| Resource limit detection (neurodesktop's `detect_resource_limits.sh`) | startup hook: reads cgroup limits so tools use the pod's CPUs | 1 |
| Home defaults restore (neurodesktop's `/opt/jovyan_defaults`) | startup hook; one mechanism with the sciget seeding hook | 1 |

The three git-related packages follow `jupyterlab-git`: drop the extension and
they become catalogue entries too.

### Moved out of the base by the rule

| Component | Delivered instead as |
| --- | --- |
| Firefox | a sciget container (its own sandbox needs testing inside Apptainer first) |
| LXQt apps: `featherpad`, `qps`, `lximage-qt`, `lxqt-archiver` | sciget containers with desktop launchers |
| `jq`, `rsync`, `htop`, `unzip` | sciget containers with command wrappers |

The cost of containerising small command-line tools: each call starts
Apptainer (a fraction of a second), and the tool sees only the paths sciget
binds (home, `/tmp`, the working directory). Pipes and terminals work.

## B. Generic but heavy: deliver as containers through sciget, not in the base

Decided 2026-11-16: these stay out of the base image. They are delivered as
containers through sciget, from CVMFS where the node has it (fast first use,
only the files used are fetched) or pulled from a registry and converted to a
SIF otherwise (works anywhere, slower first use). The base keeps only what is
on the startup path plus small essentials.

| Component | Note |
| --- | --- |
| VS Code in the browser (`code-server`) | large, and neurodesktop patches its bundled npm dependencies; jupyter-server-proxy can launch it through `apptainer exec` |
| Extra kernels (R, Julia, large Python stacks) | a kernel spec can point into a container, keeping `jupyter-env` small |
| PDF export of notebooks (TinyTeX) | reached through a wrapper command, as neurocommand does |
| Research data management | `git-annex`, `datalad` (used beyond neuroimaging) |
| AI command-line tools | Codex, Claude Code, OpenCode; they update often, which suits catalogue publishing |
| Cloud sync tools that need no mount | `rclone` (copy and sync); Nextcloud/ownCloud desktop clients |

## B2. Generic but cannot run as containers: derived images decide

These hook into the running system or the Jupyter server, so a derived image
adds them (OS packages or `jupyter-env` packages) when it needs them.

| Component | Why not a container |
| --- | --- |
| VirtualGL (GPU rendering via EGL) | hooks into each application's own graphics calls; likely needed by microscopy as much as neuroimaging |
| FUSE mounts: `sshfs`, `davfs2`, `s3fs` | mount helpers in the container's own mount namespace, some setuid |
| Slurm client and `jupyterlab-slurm` | site config, munge, a Jupyter server extension |
| AI assistants inside JupyterLab | `jupyter-ai` and its adapters are server extensions |
| Collaboration and publishing | `jupyter-collaboration`, `jupyterlab-chat`, RISE, MyST, `papermill`, `jupyter_scheduler`: server or Lab extensions |
| SSH into the container | `openssh-server`, `jupyter-sshd-proxy`: a system service |

## C. Neurodesk-specific: stay in neurodesktop

neurocommand; NiiVue (`ipyniivue`, `jupyterlab-niivue`); `nipype`, `pydra`,
`nipoppy`, `niwrap`; ASTRA tools and viewer; FreeBrowse; ITK-SNAP config; the
neurodesk launcher extension, kernel, cite and update tools; the CVMFS mirror
selection config (the mechanism could move to the base later, the server list
is Neurodesk's); Tailscale.

## D. Superseded by scidesktop

Guacamole and Tomcat, xrdp, TigerVNC, LXDE, Kasm, Glass and voxl (Selkies
replaces the streaming stack); the docker-stacks base; conda itself (mamba only).

## Notes

- neurodesktop carries about 15 `patch_*.py` files for Jupyter packages. Every
  extension added to the base brings its own patches and pins, and their
  startup cost. Keep the base to section A and measure startup after each
  addition (`test/startup-time.sh`).
- Section A adds a few tens of MB. Firefox, the largest candidate (~250 MB), is
  now a catalogue entry.
- Python packages in A go into `components/jupyter-env/environment.yml` and
  need `./lock` re-run; apt packages go into a new `components/os-ubuntu/packages/tools.txt`.
