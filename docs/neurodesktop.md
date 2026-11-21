# neurodesktop: scidesktop for neuroimaging

`neurodesktop` gives users what
[neurodesk/neurodesktop](https://github.com/neurodesk/neurodesktop) gives
them, built from scidesktop components. It is scidesktop plus six optional
components (see [images.md](images.md#optional-components)). Each one is
reusable: another image copies it with one line.

| Component | What it adds | Where |
| --- | --- | --- |
| `neurodesk-cvmfs` | the Neurodesk CVMFS repository for the base's CVMFS client: its mirrors, its public key, and the repository as the one to mount in internal mode | `/etc/cvmfs` |
| `datalad` | [DataLad](https://www.datalad.org), datalad-container and git-annex | `/opt/datalad`, commands `datalad`, `git-annex` |
| `code-server` | [code-server](https://github.com/coder/code-server) (VS Code in the browser), opened from the **VS Code** launcher tile | `/opt/code-server`, command `code-server` |
| `coding-agents`, `t3-code` | Codex, Claude Code, OpenCode and the **scigent.ai** tile ([coding-agents.md](coding-agents.md)) | `/opt/coding-agents`, `/opt/t3-code` |
| `neurodesk-agents` | Neurodesk's defaults for those agents: instructions for working with Neurodesk tools, and the Neurodesk model provider for OpenCode | `/opt/neurodesk-agents` |

`code-server` and `datalad` are generic. The two `neurodesk-*` components hold
everything that is specific to Neurodesk.

## Using the tools

The neuroimaging tools are not installed in the image. Each is a container,
and a module makes its commands available:

```sh
module avail                 # every tool and version
module spider fsl            # the versions of one tool
module load fsl/6.0.7.16     # put its commands on PATH
bet input.nii.gz output.nii.gz
```

The commands run the tool in its container through Apptainer. The first run
reads the container over the network and can take minutes.

Where the modules come from depends on the deployment:

- **`/cvmfs/neurodesk.ardc.edu.au` is mounted** (by the platform, or inside
  the container; see [CVMFS](#cvmfs)): every Neurodesk tool is a module at
  once. Nothing is downloaded until a tool runs, and then only the files it
  reads.
- **It is not mounted:** `sciget find fsl` searches the same catalog, and
  `sciget install fsl/6.0.7.16` downloads that container and writes its
  module. A new terminal finds it. The sciget button on the desktop's taskbar
  browses and launches the same containers.

On arm64, use the modules whose name ends in `_arm64` (for example
`niimath_arm64`). A module without that ending holds an amd64 container. Only
some Neurodesk tools have an arm64 container.

A tool sees the home folder, `/tmp`, the working directory and the folders
named in `APPTAINER_BINDPATH`. To give tools a data volume mounted elsewhere,
set `APPTAINER_BINDPATH` in the deployment (for example `/data`). The image
sets none, because Apptainer refuses to start when a folder in it is missing.

## Data

`datalad` and `git-annex` are on `PATH` in every terminal. They have their own
Python at `/opt/datalad`; the notebook kernels do not import `datalad`. To use
its Python API in a notebook, install it into an environment of your own (see
the [README](../README.md)).

## VS Code

Choose **VS Code** in JupyterLab's launcher. It opens in a new browser tab, at
`<session URL>/vscode/`. code-server starts when the tile is first opened; a
session that never opens it runs no code-server process.

code-server listens on a Unix socket only the user can open. Jupyter Server
Proxy is the only way to it and checks the notebook server's login on every
request, so code-server's own login is off. Its telemetry and update checks
are off too.

Settings and extensions are in `~/.local/share/code-server`. A new home gets a
`User/settings.json` that turns off self-updates and automatic port
forwarding. Extensions come from [Open VSX](https://open-vsx.org); none is
preinstalled.

| Variable | Default | Purpose |
| --- | --- | --- |
| `CODE_SERVER_WORKDIR` | the home folder | The folder VS Code opens |

## Coding agents

`codex`, `claude`, `opencode` and the **scigent.ai** tile work as
[coding-agents.md](coding-agents.md) describes. `neurodesk-agents` adds two
things, both through that component's extension points:

- **Instructions.** `/opt/neurodesk-agents/AGENTS.md` tells an agent how this
  image works: tools are modules, load exact versions, use `sciget` when CVMFS
  is not mounted, use DataLad for data, write steps as scripts. A new home
  gets links to it where each agent reads its user-level instructions:
  `~/.codex/AGENTS.md`, `~/.claude/CLAUDE.md` and
  `~/.config/opencode/AGENTS.md`. They are links, so a newer image brings
  newer instructions. Replace a link with a file of your own to change them.
- **The Neurodesk model provider for OpenCode.**
  `/opt/neurodesk-agents/opencode.json` defines the provider `neurodesk`
  (`https://llm.neurodesk.org/openai`). A start hook sets `OPENCODE_CONFIG` to
  that file. OpenCode merges it with `~/.config/opencode/opencode.json`, which
  stays the user's own.

The provider needs a key and the image has none. Set `NEURODESK_API_KEY` in
the session (a JupyterHub profile's environment, or `export` in a terminal);
get a key from the Neurodesk project. Then choose the model
`neurodesk/neurodesk` in OpenCode. No default model is preset: without a key OpenCode behaves as in any other
image.

| Variable | Default | Purpose |
| --- | --- | --- |
| `NEURODESK_API_KEY` | unset | The key for the Neurodesk model provider |
| `OPENCODE_CONFIG` | `/opt/neurodesk-agents/opencode.json` | OpenCode's extra configuration file (OpenCode's own variable). A value set by the deployment is kept |

## CVMFS

The base decides how CVMFS is delivered
([operator runbook](operator-runbook.md#environment)). This image
adds the Neurodesk repository's configuration, so both ways work without
further files:

| `SCIDESKTOP_CVMFS_MODE` | What happens |
| --- | --- |
| `external` (default) | The platform mounts `/cvmfs` (a CSI driver, a host mount). The image mounts nothing. This is how JupyterHub on Kubernetes runs it |
| `internal` | The container mounts `neurodesk.ardc.edu.au` itself at start. It must start as root with `/dev/fuse`, the capability to mount and an AppArmor profile that allows it: `--user root --cap-add SYS_ADMIN --device /dev/fuse --security-opt apparmor=unconfined` |
| `disabled` | Nothing is mounted. Tools come from `sciget install` |

`SCIDESKTOP_CVMFS_REPOSITORIES` defaults to `neurodesk.ardc.edu.au` in this
image; a value set by the deployment is kept. The client orders the
repository's six mirrors by distance (GeoAPI) and moves to the next when one
fails.

## What was ported from neurodesktop

neurodesktop at `575b20e` (2026-11-19), every user-visible capability. An
earlier review of what belongs in the base is in
[neurodesktop-components-review.md](neurodesktop-components-review.md).

**(a) Already in scidesktop**

| neurodesktop | In scidesktop |
| --- | --- |
| JupyterLab, JupyterHub single-user server, docker-stacks start hooks | `startup`, `jupyter-env` |
| Desktop in the browser (Guacamole, Tomcat, TigerVNC, xrdp, LXDE, voxl) | `selkies` with IceWM: one port, no second login |
| Apptainer, `singularity` command, GPU binding (`APPTAINER_NV`) | `apptainer` |
| CVMFS client and its mount at start | the OS layer's client and `20-cvmfs` hook |
| Lmod, the module panel in JupyterLab (`jupyterlmod`) | `lmod`, `jupyter-env` |
| `MODULEPATH` with one folder per Neurodesk category | `sciget`'s `/etc/scidesktop/modulepath.d/60-neurodesk-cvmfs` |
| Offline modules in `/neurodesktop-storage/containers` when CVMFS is missing | `sciget install` into the home |
| neurocommand: the application menu, launchers and `fetch_and_run.sh` | sciget with the `neuroimaging` catalog (built from the same `apps.json`): `sciget ui` on the taskbar, and a launcher tile per installed graphical application |
| Home defaults restored at start | `startup`'s `/etc/scidesktop/home-defaults` |
| CPU and memory limits read from cgroups | `startup`'s `05-resource-limits.sh` |
| git, ssh client, nano, tmux, `jupyterlab-git` | the OS layer and `jupyter-env` |
| Codex, Claude Code, OpenCode | `coding-agents` |
| T3 Code tile | `t3-code` |

**(b) Generic, new components in this change**

| neurodesktop | Component |
| --- | --- |
| code-server with the VS Code tile | `code-server` |
| `datalad`, `datalad-container`, `git-annex` | `datalad` |

**(c) Neurodesk-specific, new components in this change**

| neurodesktop | Component |
| --- | --- |
| CVMFS configuration and public key for `neurodesk.ardc.edu.au` | `neurodesk-cvmfs` |
| `AGENTS.md` for the agents; the Neurodesk LLM provider for OpenCode | `neurodesk-agents`. The instructions are written for this image, not copied: neurodesktop's describe Slurm, ASTRA and wrapper scripts this image does not have |

**(d) Deliberately not ported**

| neurodesktop | Why |
| --- | --- |
| Guacamole, Tomcat, VNC, xrdp, LXDE, voxl, Kasm, Glass | Selkies replaces the streaming stack |
| The webapp container launcher | Out of scope here; a containerised web application is a sciget concern |
| Tailscale, cloudflared, T3 Connect | Remote pairing needs a relay client and a sign-in the image cannot hold |
| The agent wrapper scripts (`/usr/local/sbin/{claude,codex,opencode}`) and their interactive key prompts | The agents are upstream binaries here. The wrappers save keys into `~/.bashrc` and copy instructions into every working directory |
| Agent defaults that switch off approvals (Codex `approval_policy = "never"` with `danger-full-access`, Claude `allow: Bash, Edit, Write`) | A default for one community's risk appetite; a deployment that wants them puts them in `/etc/scidesktop/home-defaults` |
| Brain Researcher MCP server | It needs a personal token (`BR_MCP_TOKEN`). See [below](#brain-researcher) for how a user adds it |
| The CVMFS mirror selection by measured speed | about 700 lines of start-time probing. The client's GeoAPI ordering and failover cover the same failure |
| `sudo` for `apt`, the `apt` wrapper | scidesktop sessions have no root; software arrives as containers or user environments |

## Not in this change

Each of these is a follow-up of its own. None blocks using the image.

| neurodesktop | Why it waits |
| --- | --- |
| A neuroimaging Python kernel (`nipype`, `nibabel`, `niwrap`, `pydra`, `nipoppy`, `ipyniivue`) | A kernel component with a large lock, like `ai-ready`'s. It needs its own review |
| NiiVue and FreeBrowse viewers in JupyterLab | Lab extensions go into `jupyter-env`, which every image shares |
| Jupyter AI and Notebook Intelligence | Server extensions in `jupyter-env`, with neurodesktop's patches to carry |
| Slurm (a local single-node cluster) and `jupyterlab-slurm` | System services and munge; a component that starts daemons |
| SSH into the session (`openssh-server`, `jupyter-sshd-proxy`) | A system service and a server extension |
| VS Code extensions preinstalled | neurodesktop installs them from the network at every start; a locked set needs a design |
| The `neurodesk` command (`cite`, `kernel add`, `check`) | Depends on the kernel wrapper and Slurm above |
| Nextflow, nf-test, Snakemake, TinyTeX | Generic, and deliverable as sciget containers |
| Firefox, rclone, sshfs, davfs2, s3fs, Nextcloud client | apt packages belong to the OS component, which every image shares |
| ASTRA and Lightcone tools | New in neurodesktop and still changing |
| The getting-started notebook tile, the launcher's categories and banner | Part of neurodesktop's launcher extension |
| VirtualGL | Hooks into applications' graphics calls; needs GPU testing |

### Brain Researcher

neurodesktop offers the [Brain Researcher](https://brain-researcher.com) MCP
server to its agents. It needs a personal token, so this image configures
nothing for it. A user with a token adds it to an agent themselves, for
example in `~/.config/opencode/opencode.json`, with the token read from the
environment (`{env:BR_MCP_TOKEN}`) and never written into the file.

## Deploying

Everything in the [operator runbook](operator-runbook.md) applies as for
scidesktop. No `cmd` or extra port is needed in a JupyterHub profile.

**Sizing.** The six components add 2.3 GB on disk to the base: 0.9 GB for the agents,
0.7 GB for code-server, 0.4 GB for T3 Code and 0.3 GB for DataLad. An open
VS Code tab holds a code-server process of a few hundred MB.

## Updating

| What | Where | How |
| --- | --- | --- |
| code-server | `CODE_SERVER_VERSION` in `docker-bake.hcl` | Renovate proposes the version. Update both `CODE_SERVER_SHA256_*` variables from the `sha256` digests of `code-server-<version>-linux-{amd64,arm64}.tar.gz` on the GitHub release |
| DataLad, git-annex | `components/datalad/requirements.in` | Change the pin, run `components/datalad/lock` |
| The CVMFS mirrors or key | `components/neurodesk-cvmfs/rootfs/etc/cvmfs` | Edit the file. The manifest entry records the key's fingerprint |
| The agents' instructions, the provider | `components/neurodesk-agents/rootfs/opt/neurodesk-agents` | Edit the file |

Check the image with:

```sh
docker buildx bake neurodesktop code-server-test datalad-test neurodesk-cvmfs-test neurodesk-agents-test
./test/image-smoke.sh neurodesktop
```

`test/neurodesk-cvmfs-smoke.sh` mounts the repository, loads a module and
runs its tool. It needs `/dev/fuse` on the host and the network to the
Neurodesk mirrors. On a host without `/dev/fuse` it prints `NOT TESTED` and
checks only the configuration.

## Licences

| What | Licence | In the image |
| --- | --- | --- |
| code-server | MIT; VS Code's and its bundled packages' notices come with the release | `/opt/code-server/LICENSE`, `/opt/code-server/ThirdPartyNotices.txt` |
| DataLad, datalad-container | MIT | `/opt/datalad/lib/python3.13/site-packages/datalad-*.dist-info/licenses` |
| git-annex | AGPL-3.0-or-later. The image carries its upstream's PyPI build, unmodified | `/opt/datalad/licenses/git-annex-AGPL`, and `git-annex-SOURCE`, which says where the source of this version is |
| The CVMFS configuration, the public key and the provider definition | MIT, from neurodesktop (Copyright (c) 2021 NeuroDesk) | `/etc/cvmfs`, `/opt/neurodesk-agents/opencode.json` |
