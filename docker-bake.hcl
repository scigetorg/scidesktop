# scidesktop build graph. Each component under components/ builds independently and
# in parallel; the assembly copies their outputs onto the OS layer.
#
#   docker buildx bake                  # the image (default group)
#   docker buildx bake test             # every component's test stage
#   docker buildx bake os-ubuntu-test   # one component's test
#
# Components build only through bake: it supplies their versions.
#
# Components that compile native code build FROM the OS layer (context "os") so
# they link against the same libraries they run with.

# --- Versions ---------------------------------------------------------------
# Every version, digest and checksum the components build with, each in one place.
# Component Dockerfiles declare these as ARGs without values; each target below
# passes only the ones its component uses. Python package pins live in each component's
# environment.yml / requirements.in instead.
#
# Renovate updates every variable carrying a "# renovate:" comment. Keep each
# variable on one line: the comment, then `variable "NAME" { default = "..." }`.
# Checksums are not updated by Renovate; a version bump fails the build until
# its checksum is updated too. A file that differs per architecture has one
# checksum variable per architecture: NAME_SHA256_AMD64, NAME_SHA256_ARM64.

# renovate: datasource=docker depName=ubuntu
variable "UBUNTU" { default = "26.04@sha256:065aa8626841f16057b78b027b464cd59c4fac36c204c72dcbf48d66f5fa8a96" }
# Ubuntu archive snapshot; moved weekly by .github/workflows/apt-snapshot.yml.
variable "APT_SNAPSHOT" { default = "20261115T000000Z" }
# renovate: datasource=github-releases depName=cvmfs/cvmfs extractVersion=^cvmfs-(?<version>.*)$
variable "CVMFS_VERSION" { default = "2.13.3" }
variable "CVMFS_CONFIG_VERSION" { default = "1.1-0" }

# renovate: datasource=github-releases depName=mamba-org/micromamba-releases
variable "MICROMAMBA_VERSION" { default = "2.10.0-0" }
variable "MICROMAMBA_SHA256_AMD64" { default = "701f39c06f8e6a670a0e186c8479b9e5c0502a2f0cda6cef65d83bdd2875e8bd" }
variable "MICROMAMBA_SHA256_ARM64" { default = "3bb56786e21b9b24024f599fe9185b4a59dc3f9f59937a42311ee583adbbb23c" }

# renovate: datasource=github-releases depName=apptainer/apptainer extractVersion=^v(?<version>.*)$
variable "APPTAINER_VERSION" { default = "1.5.5" }
# renovate: datasource=docker depName=apptainer-go packageName=golang
variable "APPTAINER_GO_VERSION" { default = "1.27.4-bookworm" }
# renovate: datasource=go depName=google.golang.org/grpc
variable "APPTAINER_GRPC_VERSION" { default = "1.85.0" }
# renovate: datasource=go depName=golang.org/x/crypto
variable "APPTAINER_CRYPTO_VERSION" { default = "0.59.0" }

# renovate: datasource=github-releases depName=TACC/Lmod
variable "LMOD_VERSION" { default = "9.4.5" }
variable "LMOD_SHA256" { default = "05292b7a1d9285a869129726f1429f86393fe274bf12d311828e16df27cdaaf3" }

# renovate: datasource=docker depName=sciget-go packageName=golang
variable "SCIGET_GO_VERSION" { default = "1.27.0-bookworm" }

# The command-line coding agents (components/coding-agents). Each is its
# upstream's release binary; docs/coding-agents.md has their licences.
# renovate: datasource=github-releases depName=openai/codex extractVersion=^rust-v(?<version>.*)$
variable "CODEX_VERSION" { default = "0.167.0" }
variable "CODEX_SHA256_AMD64" { default = "9d64836106d5b374e90ee4454c7ebcde7ca7106558bd7e41a34b9f26ebda251a" }
variable "CODEX_SHA256_ARM64" { default = "843489acb4d4b1079745c36b03c5963b887b83155af208fd53584e33ee8eb281" }
# renovate: datasource=npm depName=claude-code packageName=@anthropic-ai/claude-code
variable "CLAUDE_CODE_VERSION" { default = "2.1.316" }
variable "CLAUDE_CODE_SHA256_AMD64" { default = "fd13c70000fec3f2116dfbcbb6121210b4a29328bf0e46210a59dd594a67d824" }
variable "CLAUDE_CODE_SHA256_ARM64" { default = "55cdb8e162d190432696ea54010e0fca2e18d06fa7a7127fd563b9ffd4f22624" }
# renovate: datasource=npm depName=opencode packageName=@opencode/cli
variable "OPENCODE_VERSION" { default = "2.2.5" }
variable "OPENCODE_SHA256_AMD64" { default = "92690eee07a680d3cb760ca02ba43878de9eab1b4e5d5dfae8795518c53628f4" }
variable "OPENCODE_SHA256_ARM64" { default = "f8c5a82075fede9b5b044ed6c8a6d13ad807a7e62caea1cd0a878adef49eb053" }

# T3 Code (components/t3-code). Its base-path adapter is written against the
# web client of this release; the component's test says when a bump moves it.
# renovate: datasource=github-releases depName=pingdotgg/t3code extractVersion=^v(?<version>.*)$
variable "T3_CODE_VERSION" { default = "0.1.5" }
variable "T3_CODE_SHA256_AMD64" { default = "21d50dcc9c634221b11b58d6a94350d2c6ee36905737b054b11fa4eba295a98b" }
variable "T3_CODE_SHA256_ARM64" { default = "389362e2a349ea62b38d9bc708f4fca2381936cccb2d326b5fc5d074b072aef1" }

# code-server (components/code-server): the upstream release, unmodified.
# renovate: datasource=github-releases depName=coder/code-server extractVersion=^v(?<version>.*)$
variable "CODE_SERVER_VERSION" { default = "4.145.2" }
variable "CODE_SERVER_SHA256_AMD64" { default = "2f6db6c3e8b733dd6b3aeee83532e148b2bae2e392353ba85452d03572348962" }
variable "CODE_SERVER_SHA256_ARM64" { default = "e867a34416e2da4a83496b09580001893e7a4e5bb58a0624c4fcd22819e7d53d" }

# The NiiVue viewer for JupyterLab (components/jupyterlab-niivue): the wheel
# on PyPI, one file for every architecture.
# renovate: datasource=pypi depName=jupyterlab-niivue
variable "JUPYTERLAB_NIIVUE_VERSION" { default = "0.2.7" }
variable "JUPYTERLAB_NIIVUE_SHA256" { default = "192d71973065358fd6151ad2c6fef2e207275d3323f175e682ab7d30686b33a7" }

# FreeBrowse for JupyterLab (components/jupyterlab-freebrowse) is built with
# this Node.js. Its source is FREEBROWSE_COMMIT below.
# renovate: datasource=docker depName=freebrowse-node packageName=node
variable "FREEBROWSE_NODE_VERSION" { default = "24.22.3-bookworm-slim" }

# The VS Code extensions neurodesktop gives its users
# (components/neurodesk-vscode), from Open VSX. Three are published per
# platform and have a checksum per architecture; the others are one file.
# renovate: datasource=custom.open-vsx depName=anthropic.claude-code packageName=Anthropic/claude-code
variable "VSCODE_CLAUDE_CODE_VERSION" { default = "2.1.330" }
variable "VSCODE_CLAUDE_CODE_SHA256_AMD64" { default = "e021a291fa6863326ed955485e734c8b71ccd784afb2702a3537287007881957" }
variable "VSCODE_CLAUDE_CODE_SHA256_ARM64" { default = "2e29d36e93db8da8ce0d57ca4e633cac80e8d3c673279406cd6b92be098d8800" }
# renovate: datasource=custom.open-vsx depName=openai.chatgpt packageName=openai/chatgpt
variable "VSCODE_CHATGPT_VERSION" { default = "26.51117.41037" }
variable "VSCODE_CHATGPT_SHA256_AMD64" { default = "24bb529a21656afae3cecc69c7efc42a58e0fee55944c8a3d175a45274954497" }
variable "VSCODE_CHATGPT_SHA256_ARM64" { default = "0812b26dc04cfb6cf624f03222a9397a43e3bc9ef34d69996dc147df43d819ee" }
# renovate: datasource=custom.open-vsx depName=ms-python.python packageName=ms-python/python
variable "VSCODE_PYTHON_VERSION" { default = "2026.10.0" }
variable "VSCODE_PYTHON_SHA256_AMD64" { default = "4a05e50fee8d6c613a4a17f3ee1c9c0e318f0d9bcfa636dbe079d9c8e1506e05" }
variable "VSCODE_PYTHON_SHA256_ARM64" { default = "f16870f6eb1b4303d04189029cf402c81ea5a5595323127eb4e69fa4141e9a95" }
# renovate: datasource=custom.open-vsx depName=ms-toolsai.jupyter packageName=ms-toolsai/jupyter
variable "VSCODE_JUPYTER_VERSION" { default = "2025.9.1" }
variable "VSCODE_JUPYTER_SHA256" { default = "110660656944c4ab0ff687db488c2e8c59c67ec121dcf09bcaa54b6edd9ce71f" }
# renovate: datasource=custom.open-vsx depName=github.vscode-pull-request-github packageName=GitHub/vscode-pull-request-github
variable "VSCODE_GITHUB_PR_VERSION" { default = "0.174.0" }
variable "VSCODE_GITHUB_PR_SHA256" { default = "d777b9c7d59bc1e34a93366633ac254a4299110df3fa77eb4e5fa3ba2d49ed5f" }
# renovate: datasource=custom.open-vsx depName=repreng.csv packageName=ReprEng/csv
variable "VSCODE_CSV_VERSION" { default = "1.5.2" }
variable "VSCODE_CSV_SHA256" { default = "8e3dc016152ce46ec57bc5c0a93144e442b396a4bcff40681ef87f3b06dc8a10" }
# renovate: datasource=custom.open-vsx depName=korbinianeckstein.niivue packageName=KorbinianEckstein/niivue
variable "VSCODE_NIIVUE_VERSION" { default = "2.11.168" }
variable "VSCODE_NIIVUE_SHA256" { default = "df0a0ed8a644ff07c59cb601dbd726be536facc7425886a397500c739ef8a228" }
# renovate: datasource=custom.open-vsx depName=xy-sss.slurm--extension packageName=xy-sss/slurm--extension
variable "VSCODE_SLURM_VERSION" { default = "0.17.0" }
variable "VSCODE_SLURM_SHA256" { default = "7b32d4bb9c4849eaf9a2b8c1807dd7aef32ca7bb5ddee7ae15278d5e788aad4b" }

# The notebook user, set in the OS layer and used by components that own files.
variable "NB_USER" { default = "jovyan" }
variable "NB_UID" { default = "1000" }
variable "NB_GID" { default = "100" }

# --- Build settings ---------------------------------------------------------

# The platform to build, for example linux/arm64. Empty builds for the machine
# the builder runs on, which is what loads into the local image store. One
# platform per run: CI builds each on its own runner and joins them when it
# publishes.
variable "PLATFORM" { default = "" }
variable "IMAGE" { default = "scidesktop:latest" }
variable "MICRODESKTOP_IMAGE" { default = "microdesktop:latest" }
variable "AIDESKTOP_IMAGE" { default = "aidesktop:latest" }
variable "NEURODESKTOP_IMAGE" { default = "neurodesktop:latest" }
# sciget is built from source at this commit until it publishes an image
# (Renovate tracks its main branch). For local sciget development, build your
# working copy instead: SCIGET_SRC=../sciget docker buildx bake --allow=fs.read=..
variable "SCIGET_COMMIT" { default = "56c2f310188ad60f58ded74f811bd3e889c19882" }
variable "SCIGET_SRC" { default = "https://github.com/scigetorg/sciget.git#${SCIGET_COMMIT}" }
# Intersect Australia's AI Ready workshop (Apache-2.0): its notebooks, DAGs and
# requirements are taken from this commit (Renovate tracks its main branch).
# After changing it, run components/ai-ready/lock.
variable "AI_READY_COMMIT" { default = "26250b89d323c9981fc1a88c9fe2c0f69993b58d" }
variable "AI_READY_SRC" { default = "https://github.com/IntersectAustralia/ai-ready-containers.git#${AI_READY_COMMIT}" }

# FreeBrowse is built from Neurodesk's fork (BSD-2-Clause), which has no
# release, at this commit (Renovate tracks its main branch).
variable "FREEBROWSE_COMMIT" { default = "5f64059c81b7b9eb01ca6a0d261aeb17d27053d2" }
variable "FREEBROWSE_SRC" { default = "https://github.com/neurodesk/freebrowse.git#${FREEBROWSE_COMMIT}" }

# Every image in images/; building one builds the images it is FROM.
group "default" {
  targets = ["scidesktop", "microdesktop", "aidesktop", "neurodesktop"]
}

group "test" {
  targets = [
    "os-ubuntu-test",
    "startup-test",
    "jupyter-env-test",
    "selkies-test",
    "apptainer-test",
    "lmod-test",
    "sciget-test",
    "slurm-test",
    "sciget-neuroimaging-test",
    "sciget-microscopy-test",
    "jupyterlab-niivue-test",
    "jupyterlab-freebrowse-test",
    "micromamba-test",
    "ai-ready-test",
    "coding-agents-test",
    "t3-code-test",
    "code-server-test",
    "datalad-test",
    "neurodesk-cvmfs-test",
    "neurodesk-agents-test",
    "neurodesk-cli-test",
    "neurodesk-vscode-test",
  ]
}

target "_common" {
  platforms = PLATFORM == "" ? [] : [PLATFORM]
}

# --- OS layer ---------------------------------------------------------------

# The runtime OS layer the image is assembled on.
target "os-ubuntu" {
  inherits = ["_common"]
  context  = "components/os-ubuntu"
  target   = "os"
  contexts = {
    tests      = "test"
    components = "components"
  }
  args = {
    UBUNTU_IMAGE         = "docker.io/library/ubuntu:${UBUNTU}"
    APT_CACHE_ID         = "ubuntu-${regex("^[^@]+", UBUNTU)}"
    APT_SNAPSHOT         = APT_SNAPSHOT
    CVMFS_VERSION        = CVMFS_VERSION
    CVMFS_CONFIG_VERSION = CVMFS_CONFIG_VERSION
    NB_USER              = NB_USER
    NB_UID               = NB_UID
    NB_GID               = NB_GID
  }
}

# The OS layer as installed from the snapshot, before its runtime integration files. Components
# that compile against the OS build FROM it ("os-build"), so changes to the
# OS's own integration files do not rebuild them.
target "os-ubuntu-build" {
  inherits = ["os-ubuntu"]
  target   = "build"
}

target "os-ubuntu-test" {
  inherits = ["os-ubuntu"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# --- Components ------------------------------------------------------------------

# Every component: "os" is the runtime OS its test runs on, "os-build" the OS it
# compiles against; UBUNTU_IMAGE is for the stage that lays out its rootfs/.
target "_component" {
  inherits = ["_common"]
  args = {
    UBUNTU_IMAGE = "docker.io/library/ubuntu:${UBUNTU}"
    APT_CACHE_ID = "ubuntu-${regex("^[^@]+", UBUNTU)}"
  }
  contexts = {
    os         = "target:os-ubuntu"
    os-build   = "target:os-ubuntu-build"
    micromamba = "target:micromamba"
    tests      = "test"
    components = "components"
  }
}

# A build tool for the conda-based components; not copied into the image.
target "micromamba" {
  inherits = ["_common"]
  contexts = {
    os         = "target:os-ubuntu"
    components = "components"
  }
  context = "components/micromamba"
  target  = "component"
  args = {
    UBUNTU_IMAGE            = "docker.io/library/ubuntu:${UBUNTU}"
    APT_CACHE_ID            = "ubuntu-${regex("^[^@]+", UBUNTU)}"
    MICROMAMBA_VERSION      = MICROMAMBA_VERSION
    MICROMAMBA_SHA256_AMD64 = MICROMAMBA_SHA256_AMD64
    MICROMAMBA_SHA256_ARM64 = MICROMAMBA_SHA256_ARM64
  }
}

target "startup" {
  inherits = ["_component"]
  context  = "components/startup"
  target   = "component"
}

target "startup-test" {
  inherits = ["startup"]
  target   = "test"
  output   = ["type=cacheonly"]
}

target "jupyter-env" {
  inherits = ["_component"]
  context  = "components/jupyter-env"
  target   = "component"
  args = {
    NB_UID = NB_UID
    NB_GID = NB_GID
  }
}

target "jupyter-env-test" {
  inherits = ["jupyter-env"]
  target   = "test"
  output   = ["type=cacheonly"]
}

target "selkies" {
  inherits = ["_component"]
  context  = "components/selkies"
  target   = "component"
}

target "selkies-test" {
  inherits = ["selkies"]
  target   = "test"
  output   = ["type=cacheonly"]
}

target "apptainer" {
  inherits = ["_component"]
  context  = "components/apptainer"
  target   = "component"
  args = {
    APPTAINER_VERSION        = APPTAINER_VERSION
    APPTAINER_GO_VERSION     = APPTAINER_GO_VERSION
    APPTAINER_GRPC_VERSION   = APPTAINER_GRPC_VERSION
    APPTAINER_CRYPTO_VERSION = APPTAINER_CRYPTO_VERSION
  }
}

target "apptainer-test" {
  inherits = ["apptainer"]
  target   = "test"
  output   = ["type=cacheonly"]
}

target "lmod" {
  inherits = ["_component"]
  context  = "components/lmod"
  target   = "component"
  args = {
    LMOD_VERSION = LMOD_VERSION
    LMOD_SHA256  = LMOD_SHA256
  }
}

target "lmod-test" {
  inherits = ["lmod"]
  target   = "test"
  output   = ["type=cacheonly"]
}

target "sciget" {
  inherits = ["_component"]
  context  = "components/sciget"
  target   = "component"
  contexts = { sciget-src = SCIGET_SRC }
  args = {
    SCIGET_GO_VERSION = SCIGET_GO_VERSION
    NB_UID            = NB_UID
    NB_GID            = NB_GID
  }
}

target "sciget-test" {
  inherits = ["sciget"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# A Slurm queue for the session, run as the notebook user. Slurm itself is
# in the OS layer.
target "slurm" {
  inherits = ["_component"]
  context  = "components/slurm"
  target   = "component"
  args = {
    NB_UID = NB_UID
    NB_GID = NB_GID
  }
}

target "slurm-test" {
  inherits = ["slurm"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: the catalog of tools sciget offers every user of an image. An
# image copies one of them. Their tests run sciget, so they borrow it.
target "sciget-neuroimaging" {
  inherits = ["_component"]
  context  = "components/sciget-neuroimaging"
  target   = "component"
  contexts = { sciget = "target:sciget" }
}

target "sciget-neuroimaging-test" {
  inherits = ["sciget-neuroimaging"]
  target   = "test"
  output   = ["type=cacheonly"]
}

target "sciget-microscopy" {
  inherits = ["_component"]
  context  = "components/sciget-microscopy"
  target   = "component"
  contexts = { sciget = "target:sciget" }
}

target "sciget-microscopy-test" {
  inherits = ["sciget-microscopy"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: file viewers for JupyterLab. Each is a JupyterLab extension and a
# server extension outside the Jupyter environment; their builds and tests
# borrow that environment.
target "jupyterlab-niivue" {
  inherits = ["_component"]
  context  = "components/jupyterlab-niivue"
  target   = "component"
  contexts = { jupyter-env = "target:jupyter-env" }
  args = {
    JUPYTERLAB_NIIVUE_VERSION = JUPYTERLAB_NIIVUE_VERSION
    JUPYTERLAB_NIIVUE_SHA256  = JUPYTERLAB_NIIVUE_SHA256
  }
}

target "jupyterlab-niivue-test" {
  inherits = ["jupyterlab-niivue"]
  target   = "test"
  output   = ["type=cacheonly"]
}

target "jupyterlab-freebrowse" {
  inherits = ["_component"]
  context  = "components/jupyterlab-freebrowse"
  target   = "component"
  contexts = {
    jupyter-env    = "target:jupyter-env"
    freebrowse-src = FREEBROWSE_SRC
  }
  args = {
    FREEBROWSE_NODE_VERSION = FREEBROWSE_NODE_VERSION
    FREEBROWSE_COMMIT       = FREEBROWSE_COMMIT
  }
}

target "jupyterlab-freebrowse-test" {
  inherits = ["jupyterlab-freebrowse"]
  target   = "test"
  output   = ["type=cacheonly"]
}

target "micromamba-test" {
  inherits = ["micromamba"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: not in the base. The aidesktop image copies it.
target "ai-ready" {
  inherits = ["_component"]
  context  = "components/ai-ready"
  target   = "component"
  contexts = { ai-ready-src = AI_READY_SRC }
  args = {
    AI_READY_COMMIT = AI_READY_COMMIT
  }
}

target "ai-ready-test" {
  inherits = ["ai-ready"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: Codex, Claude Code and OpenCode for terminals. Every domain image
# copies it; the base does not.
target "coding-agents" {
  inherits = ["_component"]
  context  = "components/coding-agents"
  target   = "component"
  args = {
    CODEX_VERSION            = CODEX_VERSION
    CODEX_SHA256_AMD64       = CODEX_SHA256_AMD64
    CODEX_SHA256_ARM64       = CODEX_SHA256_ARM64
    CLAUDE_CODE_VERSION      = CLAUDE_CODE_VERSION
    CLAUDE_CODE_SHA256_AMD64 = CLAUDE_CODE_SHA256_AMD64
    CLAUDE_CODE_SHA256_ARM64 = CLAUDE_CODE_SHA256_ARM64
    OPENCODE_VERSION         = OPENCODE_VERSION
    OPENCODE_SHA256_AMD64    = OPENCODE_SHA256_AMD64
    OPENCODE_SHA256_ARM64    = OPENCODE_SHA256_ARM64
  }
}

target "coding-agents-test" {
  inherits = ["coding-agents"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: T3 Code behind the notebook server, as the scigent.ai tile. Its
# test runs it through a notebook server, so it borrows the Jupyter
# environment.
target "t3-code" {
  inherits = ["_component"]
  context  = "components/t3-code"
  target   = "component"
  contexts = { jupyter-env = "target:jupyter-env" }
  args = {
    T3_CODE_VERSION      = T3_CODE_VERSION
    T3_CODE_SHA256_AMD64 = T3_CODE_SHA256_AMD64
    T3_CODE_SHA256_ARM64 = T3_CODE_SHA256_ARM64
  }
}

target "t3-code-test" {
  inherits = ["t3-code"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: code-server (VS Code in the browser) as the VS Code tile.
target "code-server" {
  inherits = ["_component"]
  context  = "components/code-server"
  target   = "component"
  args = {
    CODE_SERVER_VERSION      = CODE_SERVER_VERSION
    CODE_SERVER_SHA256_AMD64 = CODE_SERVER_SHA256_AMD64
    CODE_SERVER_SHA256_ARM64 = CODE_SERVER_SHA256_ARM64
  }
}

target "code-server-test" {
  inherits = ["code-server"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: DataLad and git-annex for terminals, in their own interpreter.
target "datalad" {
  inherits = ["_component"]
  context  = "components/datalad"
  target   = "component"
}

target "datalad-test" {
  inherits = ["datalad"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: the Neurodesk CVMFS repository's configuration and public key.
target "neurodesk-cvmfs" {
  inherits = ["_component"]
  context  = "components/neurodesk-cvmfs"
  target   = "component"
}

target "neurodesk-cvmfs-test" {
  inherits = ["neurodesk-cvmfs"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: Neurodesk's defaults for the coding agents, through the
# coding-agents component's extension points. Its test gives a new home its
# defaults and runs OpenCode, so it borrows those two components.
target "neurodesk-agents" {
  inherits = ["_component"]
  context  = "components/neurodesk-agents"
  target   = "component"
  contexts = {
    coding-agents = "target:coding-agents"
    startup       = "target:startup"
  }
}

target "neurodesk-agents-test" {
  inherits = ["neurodesk-agents"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: the VS Code extensions neurodesktop gives its users, in
# code-server's system extensions folder. Its test borrows code-server and
# the Jupyter environment's Python.
target "neurodesk-vscode" {
  inherits = ["_component"]
  context  = "components/neurodesk-vscode"
  target   = "component"
  contexts = {
    code-server = "target:code-server"
    jupyter-env = "target:jupyter-env"
  }
  args = {
    VSCODE_CLAUDE_CODE_VERSION      = VSCODE_CLAUDE_CODE_VERSION
    VSCODE_CLAUDE_CODE_SHA256_AMD64 = VSCODE_CLAUDE_CODE_SHA256_AMD64
    VSCODE_CLAUDE_CODE_SHA256_ARM64 = VSCODE_CLAUDE_CODE_SHA256_ARM64
    VSCODE_CHATGPT_VERSION          = VSCODE_CHATGPT_VERSION
    VSCODE_CHATGPT_SHA256_AMD64     = VSCODE_CHATGPT_SHA256_AMD64
    VSCODE_CHATGPT_SHA256_ARM64     = VSCODE_CHATGPT_SHA256_ARM64
    VSCODE_PYTHON_VERSION           = VSCODE_PYTHON_VERSION
    VSCODE_PYTHON_SHA256_AMD64      = VSCODE_PYTHON_SHA256_AMD64
    VSCODE_PYTHON_SHA256_ARM64      = VSCODE_PYTHON_SHA256_ARM64
    VSCODE_JUPYTER_VERSION          = VSCODE_JUPYTER_VERSION
    VSCODE_JUPYTER_SHA256           = VSCODE_JUPYTER_SHA256
    VSCODE_GITHUB_PR_VERSION        = VSCODE_GITHUB_PR_VERSION
    VSCODE_GITHUB_PR_SHA256         = VSCODE_GITHUB_PR_SHA256
    VSCODE_CSV_VERSION              = VSCODE_CSV_VERSION
    VSCODE_CSV_SHA256               = VSCODE_CSV_SHA256
    VSCODE_NIIVUE_VERSION           = VSCODE_NIIVUE_VERSION
    VSCODE_NIIVUE_SHA256            = VSCODE_NIIVUE_SHA256
    VSCODE_SLURM_VERSION            = VSCODE_SLURM_VERSION
    VSCODE_SLURM_SHA256             = VSCODE_SLURM_SHA256
  }
}

target "neurodesk-vscode-test" {
  inherits = ["neurodesk-vscode"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: the `neurodesk` command (cite, kernel, check, info). Its test
# runs it with Lmod, the session's Slurm queue and the Jupyter environment's
# Python, so it borrows those three components.
target "neurodesk-cli" {
  inherits = ["_component"]
  context  = "components/neurodesk-cli"
  target   = "component"
  contexts = {
    lmod        = "target:lmod"
    slurm       = "target:slurm"
    jupyter-env = "target:jupyter-env"
  }
}

target "neurodesk-cli-test" {
  inherits = ["neurodesk-cli"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# --- Images -----------------------------------------------------------------

# The base: the components assembled on the OS layer.
target "scidesktop" {
  inherits = ["_common"]
  context  = "images/scidesktop"
  contexts = {
    os          = "target:os-ubuntu"
    startup     = "target:startup"
    jupyter-env = "target:jupyter-env"
    selkies     = "target:selkies"
    apptainer   = "target:apptainer"
    lmod        = "target:lmod"
    sciget      = "target:sciget"
    slurm       = "target:slurm"
  }
  tags   = [IMAGE]
  output = ["type=docker"]
}

# Domain images build FROM the base by name. The named context hands them the
# scidesktop target built here, so no registry is involved (docs/images.md).
# They may also copy components the base leaves out (docs/images.md).
target "microdesktop" {
  inherits = ["_common"]
  context  = "images/microdesktop"
  contexts = {
    scidesktop-base       = "target:scidesktop"
    sciget-microscopy     = "target:sciget-microscopy"
    jupyterlab-niivue     = "target:jupyterlab-niivue"
    jupyterlab-freebrowse = "target:jupyterlab-freebrowse"
    coding-agents         = "target:coding-agents"
    t3-code               = "target:t3-code"
  }
  tags   = [MICRODESKTOP_IMAGE]
  output = ["type=docker"]
}

target "aidesktop" {
  inherits = ["_common"]
  context  = "images/aidesktop"
  contexts = {
    scidesktop-base     = "target:scidesktop"
    sciget-neuroimaging = "target:sciget-neuroimaging"
    ai-ready            = "target:ai-ready"
    coding-agents       = "target:coding-agents"
    t3-code             = "target:t3-code"
  }
  tags   = [AIDESKTOP_IMAGE]
  output = ["type=docker"]
}

# scidesktop for neuroimaging: what neurodesk/neurodesktop gives its users,
# from components (docs/neurodesktop.md).
target "neurodesktop" {
  inherits = ["_common"]
  context  = "images/neurodesktop"
  contexts = {
    scidesktop-base       = "target:scidesktop"
    sciget-neuroimaging   = "target:sciget-neuroimaging"
    neurodesk-cvmfs       = "target:neurodesk-cvmfs"
    datalad               = "target:datalad"
    jupyterlab-niivue     = "target:jupyterlab-niivue"
    jupyterlab-freebrowse = "target:jupyterlab-freebrowse"
    code-server           = "target:code-server"
    coding-agents         = "target:coding-agents"
    t3-code               = "target:t3-code"
    neurodesk-agents      = "target:neurodesk-agents"
    neurodesk-vscode      = "target:neurodesk-vscode"
    neurodesk-cli         = "target:neurodesk-cli"
  }
  tags   = [NEURODESKTOP_IMAGE]
  output = ["type=docker"]
}
