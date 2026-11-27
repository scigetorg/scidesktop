# neurodesktop: scidesktop for neuroimaging

`neurodesktop` gives users what
[neurodesk/neurodesktop](https://github.com/neurodesk/neurodesktop) gives
them, built from scidesktop components. `scidesktop` already ships all
generic capabilities shared across every desktop (`microdesktop`, `datadesktop`,
`neurodesktop`): Slurm + `jupyterlab-slurm`, VS Code (`code-server`,
`vscode-core`), DataLad (+ `datalad-osf`), workflow engines
(Nextflow, nf-test, Snakemake + Slurm executor plugin), VirtualGL,
`scigethelpers`, expanded Jupyter extensions (`bash_kernel`,
`jupyter-resource-usage`, `jupyterlab_rise`, `jupyter-scheduler`,
`nbgitpuller`, `papermill`, `pytest`, `anywidget`, `ipycanvas`, `uv`), remote
mount/transfer tools (`rclone`, `sshfs`, `davfs2`, `s3fs`, `rsync`, `aria2`,
`gh`), the FreeBrowse viewer, coding agents, ACP adapters, T3 Code and
T3 Connect.

`neurodesktop` adds eight neuroimaging-specific components (see
[images.md](images.md#optional-components)) on top:

| Component | What it adds | Where |
| --- | --- | --- |
| `sciget-neuroimaging` | narrows sciget to the `neuroimaging` catalog ([images.md](images.md#tool-catalogs)) | `/etc/sciget/catalogs.json` |
| `neurodesk-cvmfs` | the Neurodesk CVMFS repository for the base's CVMFS client: its mirrors, its public key, and the repository as the one to mount in internal mode | `/etc/cvmfs` |
| `vscode-niivue` | `korbinianeckstein.niivue` VS Code extension for NIfTI and medical images | `/usr/local/share/code-server/extensions` |
| `vscode-coding-agents` | Claude Code and Codex VS Code extensions | `/usr/local/share/code-server/extensions` |
| `jupyterlab-niivue` | NiiVue JupyterLab viewer (default for `.nii`/`.nii.gz`; [viewers.md](viewers.md)) | `/opt/jupyterlab-niivue` |
| `neurodesk-agents` | Neurodesk's defaults for the base's coding agents: instructions for working with Neurodesk tools, and the Neurodesk model provider for OpenCode | `/opt/neurodesk-agents` |
| `neuroimaging-env` | the `neuroimaging` Jupyter kernel (`nibabel`, `nipype`, `niwrap`, `pydra`, `nipoppy`, `ipyniivue` with shared JupyterLab bundle — requires JupyterLab, not standalone VS Code notebooks/static HTML, `datalad`, `datalad-osf`, `osfclient`, `xnat`, `watermark`, `nf-core`) and neuroimaging CLIs (`nf-core`, `nipoppy`, `bosh`, `nipypecli`) | `/opt/neuroimaging-env`, `/usr/local/share/jupyter/kernels/neuroimaging`, `/usr/local/bin` |
| `neurodesk-compat` | FreeSurfer (`APPTAINERENV_SUBJECTS_DIR`) and `nf-neuro` (`NF_NEURO_MODULES_DIR`) defaults, pinned `/opt/nf-neuro/modules` (with local `.git` metadata), local `/neurodesktop-storage/containers/modules` discovery, and `~/getting-started.ipynb` | `/opt/nf-neuro/modules`, `/etc/scidesktop/home-defaults/getting-started.ipynb` |

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
named in `APPTAINER_BINDPATH`. At startup, the image auto-populates
`APPTAINER_BINDPATH` with whichever of `/data`, mounted `/mnt`, populated
`/cvmfs`, and (in `neurodesktop`) `/neurodesktop-storage` actually exist and
are readable by the session user. Any deployment override (`APPTAINER_BIND`,
`APPTAINER_BINDPATH`, `SINGULARITY_BIND`, `SINGULARITY_BINDPATH`) is kept, and
setting `APPTAINER_BINDPATH=""` explicitly opts out of auto-binding.

## Data

`datalad` (with `datalad-container` and `datalad-osf`), `osf`, and `git-annex`
are on `PATH` in every terminal from `/opt/datalad`. In `neurodesktop`, the
`neuroimaging` Jupyter kernel also includes `datalad`, `datalad-container`,
`datalad-osf`, and `osfclient` for notebook Python API usage, while the base
`python3` kernel stays lean on `/opt/conda`.

## VS Code

Choose **VS Code** in JupyterLab's launcher. It opens in a new browser tab, at
`<session URL>/vscode/`. code-server starts when the tile is first opened; a
session that never opens it runs no code-server process.

code-server listens on a Unix socket only the user can open. Jupyter Server
Proxy is the only way to it and checks the notebook server's login on every
request, so code-server's own login is off. Its telemetry and update checks
are off too.

A user's settings and own extensions are in `~/.local/share/code-server`. A
new home gets a `User/settings.json` that turns off self-updates and
automatic port forwarding. Extensions a user installs come from
[Open VSX](https://open-vsx.org).

**Preinstalled extensions.** Three reusable components supply the eight
extensions neurodesktop installs, so other images (such as `microdesktop`)
can pick only what they need:

| Component | Extensions | For |
| --- | --- | --- |
| `vscode-core` | `ms-python.python`, `ms-toolsai.jupyter`, `github.vscode-pull-request-github`, `repreng.csv`, `xy-sss.slurm--extension` | Python, notebooks, GitHub PRs, CSV tables, Slurm queue |
| `vscode-niivue` | `korbinianeckstein.niivue` | NIfTI and other medical images |
| `vscode-coding-agents` | `anthropic.claude-code`, `openai.chatgpt` | Claude Code and Codex in the editor (~1.5 GB together) |

neurodesktop downloads them into each home at every start. Here they are
installed when the image is built, each at a pinned version and checked
against its checksum, and no session downloads or copies anything: a session
without a network has them.

**System extensions: an extension point of `code-server`.** code-server
reads one folder as its system extensions,
`/usr/local/share/code-server/extensions`. The `code-server` component
starts it with that folder (`--builtin-extensions-dir`) and fills it with a
link to each extension of the code-server release. Any component adds its
own beside them with `components/code-server/install-extension`, so extensions
stay out of `code-server` itself:

```dockerfile
RUN --mount=type=bind,from=components,source=code-server/install-extension,target=/usr/local/bin/install-extension \
    install-extension <namespace> <name> "${VERSION}" "${SHA256}" /out [linux-x64|linux-arm64]
```

VS Code shows them under **Extensions > Built-in**. A user can disable one,
and can install another version of it, which then wins. A user cannot remove
one. `code-server --list-extensions` lists only a user's own extensions, so
it does not show them.

| Variable | Default | Purpose |
| --- | --- | --- |
| `CODE_SERVER_WORKDIR` | the home folder | The folder VS Code opens |

## The scigethelpers command

`scigethelpers` is the generalized helper command ported from neurodesktop's
`neurodesk` CLI, shipped by the `scigethelpers-cli` component (shared with
`microdesktop` and other domain images):

| Command | What it does |
| --- | --- |
| `scigethelpers cite [--status] [--json]` | writes `CITATIONS.md` in the home folder: a methods sentence and the reference for each container tool loaded as a module (`--status` inspects the usage log read-only) |
| `scigethelpers kernel add <module>` | registers the Python inside a tool's container as a notebook kernel; `list [--json]` and `remove` manage them |
| `scigethelpers uv <init\|rebuild\|remove\|list> [dir]` | manages project-local `uv` virtual environments and Jupyter kernels (with automatic `MODULEPATH` refresh at launch) |
| `scigethelpers check [--json] [cvmfs\|gpu\|slurm\|t3]` | read-only checks (all configured CVMFS repos, NVIDIA + VirtualGL EGL/OpenGL, Slurm partitions, local T3 state), each `PASS`, `FAIL` or `SKIP` |
| `scigethelpers info [--json] [--no-probes]` | the image's components, the session's CPUs and memory, GPUs and all configured CVMFS servers |
| `scigethelpers agent preflight [--json] [--cwd dir]` | summarizes user/workspace agent guidance, Lmod, Slurm configured node capacity, active sciget catalogs, and session checks |

`scigethelpers <command> --help` has each command's options. The standalone
commands `scigethelpers-cite`, `scigethelpers-kernel` and `scigethelpers-uv` work too.
Interactive Bash shells register tab completion for `scigethelpers` subcommands,
and the `jupyterlab-scigethelpers` component adds a **Session Helpers** tile
under **Scidesktop** in JupyterLab's Launcher (plus Command Palette entries and
a background startup tab on fresh workspaces).

`scigethelpers cite` knows what was loaded because Lmod records it: the
component sets `LMOD_PACKAGE_PATH` to a site package that appends one line
per loaded container module to `~/.local/state/scigethelpers/module-usage.tsv`.
Modules from `/cvmfs/` and modules `sciget install` wrote are recorded; nothing
leaves the session. Citations are fetched from the image's configured sciget
catalogs (`/etc/sciget/catalogs.json` and `~/.config/sciget/catalogs.json`).

`scigethelpers kernel add` needs the module's commands to be container
wrappers and a container with `ipykernel`.

The commands neurodesktop has and this image does not: `jobs`,
`update`, `test`, `t3`, `astra` and `lightcone
materialize`. Each depends on a part of neurodesktop that was not ported
([Not in this change](#not-in-this-change)). Lightcone itself is here:
upstream `lc materialize` builds outputs on the session's queue
([slurm.md](slurm.md#lightcone)), without Neurodesk's module execution.

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
| `internal` | The container mounts `neurodesk.ardc.edu.au,software.eessi.io` itself at start. It must start as root with `/dev/fuse`, the capability to mount and an AppArmor profile that allows it: `--user root --cap-add SYS_ADMIN --device /dev/fuse --security-opt apparmor=unconfined` |
| `disabled` | Nothing is mounted. Tools come from `sciget install` |

`SCIDESKTOP_CVMFS_REPOSITORIES` defaults to `neurodesk.ardc.edu.au,software.eessi.io` in this
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
| `MODULEPATH` with one folder per Neurodesk category | `sciget-all`'s `/etc/scidesktop/modulepath.d/60-neurodesk-cvmfs` (exposes all categories when `neuroimaging` is configured, and filters to domain-only CVMFS modules on narrowed non-neuroimaging images) |
| Offline modules in `/neurodesktop-storage/containers` when CVMFS is missing | `sciget install` into the home |
| neurocommand: the application menu, launchers and `fetch_and_run.sh` | sciget with `sciget-neuroimaging`'s `neuroimaging` catalog (built from the same `apps.json`): `sciget ui` on the taskbar, and a launcher tile per installed graphical application |
| Home defaults restored at start | `startup`'s `/etc/scidesktop/home-defaults` |
| CPU and memory limits read from cgroups | `startup`'s `05-resource-limits.sh` |
| Slurm (a local single-node cluster), started as root with munge, MariaDB and `slurmdbd` | `slurm`: the same queue run as the notebook user, with none of those ([slurm.md](slurm.md)); added after the first port |
| git, ssh client, nano, tmux, `jupyterlab-git` | the OS layer and `jupyter-env` |
| Codex, Claude Code, OpenCode | `coding-agents` |
| Jupyter AI, the chat panel in JupyterLab, with its Codex, Claude and OpenCode personas | `jupyter-env`, in every image, and `acp-adapters` for the Codex and Claude personas ([jupyter-ai.md](jupyter-ai.md)); added after the first port |
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
| The VS Code extensions installed into each home at start | `vscode-core`, `vscode-niivue`, `vscode-coding-agents`: the same eight, split for reuse and installed at build time for every user |
| The `neurodesk` command, the kernel wrapper and the Lmod site package behind `neurodesk cite` | `scigethelpers-cli`: `scigethelpers cite`, `kernel`, `check` and `info`, generalized for any sciget catalog |
| The NiiVue viewer (`jupyterlab-niivue`) and FreeBrowse, with NiiVue the default for NIfTI files | `jupyterlab-niivue`, `jupyterlab-freebrowse` ([viewers.md](viewers.md)); generic, added after the first port |
| `AGENTS.md` for the agents; the Neurodesk LLM provider for OpenCode | `neurodesk-agents`. The instructions are written for this image, not copied: neurodesktop's describe ASTRA, neurocommand and wrapper scripts this image does not have |

**(d) Deliberately not ported**

| neurodesktop | Why |
| --- | --- |
| Guacamole, Tomcat, VNC, xrdp, LXDE, voxl, Kasm, Glass | Selkies replaces the streaming stack |
| The webapp container launcher | Out of scope here; a containerised web application is a sciget concern |
| Tailscale (`neurodesk t3`) | It needs a tailnet and a userspace network daemon. T3 Connect, the other way to reach T3 Code remotely, is the `t3-connect` component ([t3-connect.md](t3-connect.md)) |
| The agent wrapper scripts (`/usr/local/sbin/{claude,codex,opencode}`) and their interactive key prompts | The agents are upstream binaries here. The wrappers save keys into `~/.bashrc` and copy instructions into every working directory |
| Agent defaults that switch off approvals (Codex `approval_policy = "never"` with `danger-full-access`, Claude `allow: Bash, Edit, Write`) | A default for one community's risk appetite; a deployment that wants them puts them in `/etc/scidesktop/home-defaults` |
| Brain Researcher MCP server | It needs a personal token (`BR_MCP_TOKEN`). See [below](#brain-researcher) for how a user adds it |
| The CVMFS mirror selection by measured speed | about 700 lines of start-time probing. The client's GeoAPI ordering and failover cover the same failure |
| `sudo` for `apt`, the `apt` wrapper | scidesktop sessions have no root; software arrives as containers or user environments |

## Not in this change

Each of these is deliberately left out or deferred:

| neurodesktop | Why |
| --- | --- |
| Notebook Intelligence | A second chat panel with patches of its own; Jupyter AI covers chat |
| SSH into the session (`openssh-server`, `jupyter-sshd-proxy`) | Needs a separate SSH daemon and port/auth surface |
| `neurodesk jobs`, `update`, `test`, `t3`, `agent preflight`, `astra`, `lightcone materialize` | Tied to remote-job/Tailscale/ASTRA workflows outside scidesktop. Upstream `lc materialize` replaces `lightcone materialize` ([slurm.md](slurm.md#lightcone)) |
| TinyTeX, Firefox, Nextcloud GUI client | Deliverable as user installs or sciget containers |
| ASTRA view tools, the Lightcone module adapter (`patch_modules.py`) and `neurodesk-lc-materialize` | Neurodesk-hosted preview tooling. Upstream `lc` with `astra-tools` and `astra-spec` is the `lightcone` component ([slurm.md](slurm.md#lightcone)) |

### Brain Researcher

neurodesktop offers the [Brain Researcher](https://brain-researcher.com) MCP
server to its agents. It needs a personal token, so this image configures
nothing for it. A user with a token adds it to an agent themselves, for
example in `~/.config/opencode/opencode.json`, with the token read from the
environment (`{env:BR_MCP_TOKEN}`) and never written into the file.

## Deploying

Everything in the [operator runbook](operator-runbook.md) applies as for
scidesktop. No `cmd` or extra port is needed in a JupyterHub profile.

**Sizing.** The components add 3.9 GB on disk to the base: 1.5 GB for the VS Code extensions (1.1 GB of it `openai.chatgpt`, 0.4 GB `anthropic.claude-code`, each with its own copy of its agent), under 0.1 GB for the two viewers, 0.9 GB for the agents,
0.7 GB for code-server, 0.4 GB for T3 Code and 0.3 GB for DataLad. An open
VS Code tab holds a code-server process of a few hundred MB.

## Updating

| What | Where | How |
| --- | --- | --- |
| code-server | `CODE_SERVER_VERSION` in `docker-bake.hcl` | Renovate proposes the version. Update both `CODE_SERVER_SHA256_*` variables from the `sha256` digests of `code-server-<version>-linux-{amd64,arm64}.tar.gz` on the GitHub release |
| DataLad, git-annex | `components/datalad/requirements.in` | Change the pin, run `components/datalad/lock` |
| The CVMFS mirrors or key | `components/neurodesk-cvmfs/rootfs/etc/cvmfs` | Edit the file. The manifest entry records the key's fingerprint |
| The agents' instructions, the provider | `components/neurodesk-agents/rootfs/opt/neurodesk-agents` | Edit the file |
| A VS Code extension | `VSCODE_*_VERSION` in `docker-bake.hcl` | Renovate proposes the version from Open VSX. Update its `VSCODE_*_SHA256` variables from the `sha256` file Open VSX publishes beside each download; three extensions have one per architecture |
| The `scigethelpers` command | `components/scigethelpers-cli/rootfs/opt/scigethelpers-cli` | Edit the file; each names the neurodesktop file it was generalized from |

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
| jupyterlab-niivue | BSD-2-Clause | `/opt/jupyterlab-niivue/lib/jupyterlab_niivue-*.dist-info/licenses/LICENSE` |
| FreeBrowse (Neurodesk's fork) | BSD-2-Clause; its Jupyter extension declares MIT | `/opt/jupyterlab-freebrowse/LICENSE` |
| The `scigethelpers` command, its helpers and the Lmod site package | MIT, generalized from neurodesktop (Copyright (c) 2021 NeuroDesk) | `/opt/scigethelpers-cli/LICENSE` |
| `ms-python.python`, `ms-toolsai.jupyter`, `github.vscode-pull-request-github`, `xy-sss.slurm--extension` | MIT | each extension's folder under `/usr/local/share/code-server/extensions` |
| `korbinianeckstein.niivue` | BSD-2-Clause | its folder, `LICENSE.txt` |
| `repreng.csv` | no licence declared on Open VSX; its folder carries the publisher's licence file | its folder |
| `anthropic.claude-code` | proprietary: Anthropic's terms, the same as the `claude` command in `coding-agents` | its folder |
| `openai.chatgpt` | its own licence (`LICENSE.md` in the extension) | its folder |
| git-annex | AGPL-3.0-or-later. The image carries its upstream's PyPI build, unmodified | `/opt/datalad/licenses/git-annex-AGPL`, and `git-annex-SOURCE`, which says where the source of this version is |
| The CVMFS configuration, the public key and the provider definition | MIT, from neurodesktop (Copyright (c) 2021 NeuroDesk) | `/etc/cvmfs`, `/opt/neurodesk-agents/opencode.json` |
