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
variable "APT_SNAPSHOT" { default = "20261123T000000Z" }
# renovate: datasource=github-releases depName=cvmfs/cvmfs extractVersion=^cvmfs-(?<version>.*)$
variable "CVMFS_VERSION" { default = "2.14.1" }
variable "CVMFS_SHA256_AMD64" { default = "79d7389e6e0db786919c688b51c910ff3a57168d8bd8fd696af67feca69146c9" }
variable "CVMFS_SHA256_ARM64" { default = "d398b315c245813535d4c589146358527a39808a3b2e21cab3493533a3373943" }
variable "CVMFS_LIBS_SHA256_AMD64" { default = "efe323b297f8cd44c54787e58f9d7796f17a4cb399909dc0f921917bdddddccf" }
variable "CVMFS_LIBS_SHA256_ARM64" { default = "d67756bf0dc101d0356dcc7dc3780401da8c3490b8d5c28b97dff5a7f08aef9e" }
variable "CVMFS_FUSE3_SHA256_AMD64" { default = "560a7e6ded3322642ee5bc75057031f270191a6d8bfdaa54987fb92f418126dd" }
variable "CVMFS_FUSE3_SHA256_ARM64" { default = "75fc4f76dc40c8776d925ce6e742c95800cb6a4311429cb4f715d69e32fa442b" }
variable "CVMFS_CONFIG_VERSION" { default = "1.1-0" }
variable "CVMFS_CONFIG_NONE_SHA256" { default = "b475d2ef4300040ebce400135c5dde1a2f58702d90c62544a22743cf2f720c7f" }
# renovate: datasource=github-releases depName=EESSI/filesystem-layer extractVersion=^v(?<version>.+)$
variable "EESSI_CVMFS_CONFIG_VERSION" { default = "0.6.0" }
variable "EESSI_CVMFS_CONFIG_SHA256" { default = "a226bc24d984e611e5118a65e35ff283c2838576d778336c84f7a86b9b70e681" }

# renovate: datasource=github-releases depName=mamba-org/micromamba-releases
variable "MICROMAMBA_VERSION" { default = "2.10.0-0" }
variable "MICROMAMBA_SHA256_AMD64" { default = "701f39c06f8e6a670a0e186c8479b9e5c0502a2f0cda6cef65d83bdd2875e8bd" }
variable "MICROMAMBA_SHA256_ARM64" { default = "3bb56786e21b9b24024f599fe9185b4a59dc3f9f59937a42311ee583adbbb23c" }

# renovate: datasource=github-releases depName=apptainer/apptainer extractVersion=^v(?<version>.*)$
variable "APPTAINER_VERSION" { default = "1.5.5" }
variable "APPTAINER_SHA256" { default = "d61347c9e554954ae662f40077a163d2af6422e65bbd254797606a8a36cf31c6" }
# renovate: datasource=docker depName=apptainer-go packageName=golang
variable "APPTAINER_GO_VERSION" { default = "1.27.4-bookworm" }
# renovate: datasource=go depName=google.golang.org/grpc
variable "APPTAINER_GRPC_VERSION" { default = "1.85.0" }
# renovate: datasource=go depName=golang.org/x/crypto
variable "APPTAINER_CRYPTO_VERSION" { default = "0.59.0" }
# renovate: datasource=go depName=github.com/go-jose/go-jose/v4
variable "APPTAINER_JOSE_VERSION" { default = "4.1.6" }
# renovate: datasource=go depName=github.com/klauspost/compress
variable "APPTAINER_COMPRESS_VERSION" { default = "1.18.7" }
# renovate: datasource=go depName=github.com/moby/go-archive
variable "APPTAINER_GO_ARCHIVE_VERSION" { default = "0.3.0" }

# renovate: datasource=github-releases depName=TACC/Lmod
variable "LMOD_VERSION" { default = "9.4.5" }
variable "LMOD_SHA256" { default = "05292b7a1d9285a869129726f1429f86393fe274bf12d311828e16df27cdaaf3" }

# Slurm release tag; tracked by its own Renovate rule (renovate.json).
variable "SLURM_TAG" { default = "slurm-25-11-9-1" }
variable "SLURM_SHA256" { default = "c1aa51d19899cd874b0d40c30bd9a1a380ed1643ed1d351d6d3c8b4b33afed06" }

# renovate: datasource=docker depName=sciget-go packageName=golang
variable "SCIGET_GO_VERSION" { default = "1.27.4-bookworm" }

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

# Node.js for build stages (acp-adapters, jupyterlab-freebrowse,
# jupyterlab-slurm, jupyterlab-neuroglancer). At runtime acp-adapters shares
# code-server's Node binary (/opt/code-server/lib/node).
# renovate: datasource=node-version depName=node
variable "NODE_VERSION" { default = "24.22.3" }

# T3 Code (components/t3-code). Its base-path adapter is written against the
# web client of this release; the component's test says when a bump moves it.
# renovate: datasource=github-releases depName=pingdotgg/t3code extractVersion=^v(?<version>.*)$
variable "T3_CODE_VERSION" { default = "0.1.5" }
variable "T3_CODE_SHA256_AMD64" { default = "21d50dcc9c634221b11b58d6a94350d2c6ee36905737b054b11fa4eba295a98b" }
variable "T3_CODE_SHA256_ARM64" { default = "389362e2a349ea62b38d9bc708f4fca2381936cccb2d326b5fc5d074b072aef1" }

# Google Antigravity ACP server for Gemini models in T3 Code (components/antigravity-acp).
# Version and checksums match T3 Code's embedded antigravityRelease.ts table.
variable "ANTIGRAVITY_ACP_VERSION" { default = "1.4.1" }
variable "ANTIGRAVITY_ACP_SHA256_AMD64" { default = "2e37012ceb2a5c7fc7309b6e6596234fb637ee3c62a5199f65d4cbe777871384" }
variable "ANTIGRAVITY_ACP_SHA256_ARM64" { default = "609336a1c97545487e3ddd55dbd153dc0f40f4e6534486cc1c5f4c0ebb85c2da" }

# The relay client T3 Connect uses (components/t3-connect): cloudflared's
# release executable. T3 Code checks the version it is given.
# renovate: datasource=github-releases depName=cloudflare/cloudflared
variable "T3_CLOUDFLARED_VERSION" { default = "2026.11.1" }
variable "T3_CLOUDFLARED_SHA256_AMD64" { default = "97bb3b02d23a5980fc9c15a1a270e692da1923f103f920d5b16d4931d5ab55e7" }
variable "T3_CLOUDFLARED_SHA256_ARM64" { default = "b155cec3e48e489cfb8e5c602769fb8c771083018d8881d68b4d18a791567c5a" }

# code-server (components/code-server): the upstream release, unmodified.
# renovate: datasource=github-releases depName=coder/code-server extractVersion=^v(?<version>.*)$
variable "CODE_SERVER_VERSION" { default = "4.145.2" }
variable "CODE_SERVER_SHA256_AMD64" { default = "2f6db6c3e8b733dd6b3aeee83532e148b2bae2e392353ba85452d03572348962" }
variable "CODE_SERVER_SHA256_ARM64" { default = "e867a34416e2da4a83496b09580001893e7a4e5bb58a0624c4fcd22819e7d53d" }

# The NiiVue viewer for JupyterLab (components/jupyterlab-niivue): the wheel
# on PyPI, one file for every architecture.
# renovate: datasource=pypi depName=jupyterlab-niivue
variable "JUPYTERLAB_NIIVUE_VERSION" { default = "0.3.0" }
variable "JUPYTERLAB_NIIVUE_SHA256" { default = "5b97abbbf9608960629c80f22065735eac7e585e688f3f8729492cd14f3d5e69" }

# Preinstalled VS Code extensions (components/vscode-core, vscode-niivue,
# vscode-coding-agents), from Open VSX. Three are published per
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

# VirtualGL for opt-in GPU-accelerated OpenGL rendering via headless EGL
# (components/virtualgl).
# renovate: datasource=github-releases depName=VirtualGL/virtualgl
variable "VIRTUALGL_VERSION" { default = "3.1.5" }
variable "VIRTUALGL_SHA256_AMD64" { default = "df3f7788ce41b182a47c0d298e5cd6d2d63579522cb41825970b7726e825485e" }
variable "VIRTUALGL_SHA256_ARM64" { default = "9ac238e8a18c06d84ef65444a591a7a5bb4c4ce9e8cfdd92f8a2aea35edbb5d7" }

# Scientific workflow engines (components/workflow-engines): Nextflow
# (offline fat executable) and nf-test (JAR). Snakemake is locked via conda/pip.
# Java for Nextflow and nf-test, inside workflow-engines.
# renovate: datasource=github-releases depName=adoptium/temurin21-binaries extractVersion=^jdk-(?<version>.*)$
variable "TEMURIN_JRE_VERSION" { default = "21.0.13.1+2" }
variable "TEMURIN_JRE_SHA256_AMD64" { default = "18f44fab9065217f3ba61d0eef8a7b5f3c3713aa7293001b0d4ac10ede3850f0" }
variable "TEMURIN_JRE_SHA256_ARM64" { default = "52bc58323d9266538a6361a3cf8365fc1186dd9510d7f33f623681c4aabb7e72" }

# renovate: datasource=github-releases depName=nextflow-io/nextflow extractVersion=^v(?<version>.*)$
variable "NEXTFLOW_VERSION" { default = "26.10.7" }
variable "NEXTFLOW_SHA256" { default = "c54cd4b7be058e8954180b378a8efa6d61085bc433d7d9b06ec2cad2ad6580a6" }
# renovate: datasource=github-releases depName=askimed/nf-test extractVersion=^v(?<version>.*)$
variable "NF_TEST_VERSION" { default = "0.9.5" }
variable "NF_TEST_SHA256" { default = "b7679eb90cdc9642bfa89e9634db02ce6e699de53ad35ef0e2f4847634fc1641" }
# renovate: datasource=github-releases depName=viash-io/viash
variable "VIASH_VERSION" { default = "0.9.7" }
variable "VIASH_SHA256" { default = "63f282fa1d49bc6a52fe2e25e265bce8b4223f0d8f521d38094942deb5a1ccc4" }

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
variable "DATADESKTOP_IMAGE" { default = "datadesktop:latest" }
variable "DERMDESKTOP_IMAGE" { default = "dermdesktop:latest" }
variable "PRECLINICALDESKTOP_IMAGE" { default = "preclinicaldesktop:latest" }
variable "MOLECULARDESKTOP_IMAGE" { default = "moleculardesktop:latest" }
variable "GENOMICSDESKTOP_IMAGE" { default = "genomicsdesktop:latest" }
variable "NEURODESKTOP_IMAGE" { default = "neurodesktop:latest" }
# sciget is built from source at this commit until it publishes an image
# (Renovate tracks its main branch). For local sciget development, build your
# working copy instead: SCIGET_SRC=../sciget docker buildx bake --allow=fs.read=..
variable "SCIGET_COMMIT" { default = "ac5c4abdbe35ab10a7f6d2f724b3d3ad92c3ecb4" }
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

# Google Neuroglancer standalone web client (Apache-2.0, v2.41.2) for OME-Zarr,
# N5, Precomputed, NIfTI and mesh datasets on microdesktop (Renovate tracks master).
variable "NEUROGLANCER_COMMIT" { default = "e13f1f4c62918f2ea07b12f2116bdcb6767b1499" }
variable "NEUROGLANCER_SRC" { default = "https://github.com/google/neuroglancer.git#${NEUROGLANCER_COMMIT}" }

# Slurm Queue Manager extension for JupyterLab (NERSC/jupyterlab-slurm,
# BSD-3-Clause), built from a pinned commit (Renovate tracks its main branch).
variable "JUPYTERLAB_SLURM_COMMIT" { default = "8dccb39808f8a1b77712a9a5773a7d2601a56683" }
variable "JUPYTERLAB_SLURM_SRC" { default = "https://github.com/NERSC/jupyterlab-slurm.git#${JUPYTERLAB_SLURM_COMMIT}" }

# nf-neuro Nextflow modules for neuroimaging pipelines (neurodesk-compat),
# cloned at a pinned commit (Renovate tracks its main branch).
variable "NF_NEURO_MODULES_COMMIT" { default = "98234c97094e4632b5c910141ae34c779196b2fb" }
variable "NF_NEURO_MODULES_SRC" { default = "https://github.com/nf-neuro/modules.git#${NF_NEURO_MODULES_COMMIT}" }

# Every image in images/; building one builds the images it is FROM.
group "default" {
  targets = ["scidesktop", "microdesktop", "datadesktop", "dermdesktop", "preclinicaldesktop", "moleculardesktop", "genomicsdesktop", "neurodesktop"]
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
    "sciget-all-test",
    "sciget-neuroimaging-test",
    "sciget-microscopy-test",
    "sciget-datascience-test",
    "sciget-dermatology-test",
    "sciget-preclinical-test",
    "sciget-molecular-imaging-test",
    "sciget-genomics-test",
    "eessi-cvmfs-test",
    "jupyterlab-niivue-test",
    "jupyterlab-freebrowse-test",
    "jupyterlab-neuroglancer-test",
    "micromamba-test",
    "ai-ready-test",
    "coding-agents-test",
    "acp-adapters-test",
    "antigravity-acp-test",
    "t3-code-test",
    "t3-connect-test",
    "code-server-test",
    "datalad-test",
    "lightcone-test",
    "neurodesk-cvmfs-test",
    "neurodesk-agents-test",
    "scigethelpers-cli-test",
    "vscode-core-test",
    "vscode-niivue-test",
    "vscode-coding-agents-test",
    "virtualgl-test",
    "jupyterlab-slurm-test",
    "workflow-engines-test",
    "viash-hub-test",
    "microscopy-env-test",
    "datascience-env-test",
    "dermatology-env-test",
    "preclinical-env-test",
    "molecular-imaging-env-test",
    "genomics-env-test",
    "genomics-agents-test",
    "neuroimaging-env-test",
    "neurodesk-compat-test",
    "rclone-test",
    "gh-test",
    "aria2-test",
    "tcsh-test",
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
    UBUNTU_IMAGE             = "docker.io/library/ubuntu:${UBUNTU}"
    APT_CACHE_ID             = "ubuntu-${regex("^[^@]+", UBUNTU)}"
    APT_SNAPSHOT             = APT_SNAPSHOT
    CVMFS_VERSION            = CVMFS_VERSION
    CVMFS_SHA256_AMD64       = CVMFS_SHA256_AMD64
    CVMFS_SHA256_ARM64       = CVMFS_SHA256_ARM64
    CVMFS_LIBS_SHA256_AMD64  = CVMFS_LIBS_SHA256_AMD64
    CVMFS_LIBS_SHA256_ARM64  = CVMFS_LIBS_SHA256_ARM64
    CVMFS_FUSE3_SHA256_AMD64 = CVMFS_FUSE3_SHA256_AMD64
    CVMFS_FUSE3_SHA256_ARM64 = CVMFS_FUSE3_SHA256_ARM64
    CVMFS_CONFIG_VERSION     = CVMFS_CONFIG_VERSION
    CVMFS_CONFIG_NONE_SHA256 = CVMFS_CONFIG_NONE_SHA256
    NB_USER                  = NB_USER
    NB_UID                   = NB_UID
    NB_GID                   = NB_GID
  }
}

target "os-ubuntu-test" {
  inherits = ["os-ubuntu"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# --- Components ------------------------------------------------------------------

# Every component: "os" is the runtime OS its test runs on; UBUNTU_IMAGE is for
# the build stage and the stage that lays out its rootfs/.
target "_component" {
  inherits = ["_common"]
  args = {
    UBUNTU_IMAGE = "docker.io/library/ubuntu:${UBUNTU}"
    APT_CACHE_ID = "ubuntu-${regex("^[^@]+", UBUNTU)}"
  }
  contexts = {
    os         = "target:os-ubuntu"
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
    APPTAINER_VERSION            = APPTAINER_VERSION
    APPTAINER_SHA256             = APPTAINER_SHA256
    APPTAINER_GO_VERSION         = APPTAINER_GO_VERSION
    APPTAINER_GRPC_VERSION       = APPTAINER_GRPC_VERSION
    APPTAINER_CRYPTO_VERSION     = APPTAINER_CRYPTO_VERSION
    APPTAINER_JOSE_VERSION       = APPTAINER_JOSE_VERSION
    APPTAINER_COMPRESS_VERSION   = APPTAINER_COMPRESS_VERSION
    APPTAINER_GO_ARCHIVE_VERSION = APPTAINER_GO_ARCHIVE_VERSION
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

# A Slurm queue for the session, run as the notebook user; Slurm built from
# source into /opt/slurm.
target "slurm" {
  inherits = ["_component"]
  context  = "components/slurm"
  target   = "component"
  args = {
    NB_UID       = NB_UID
    NB_GID       = NB_GID
    SLURM_TAG    = SLURM_TAG
    SLURM_SHA256 = SLURM_SHA256
  }
}

target "slurm-test" {
  inherits = ["slurm"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# The catalogs of tools sciget offers every user of an image. The base image
# copies sciget-all (every domain catalog); domain images narrow the offered
# tools by copying their own catalog component over /etc/sciget/catalogs.json.
# Their tests run sciget, so they borrow it.
target "sciget-all" {
  inherits = ["_component"]
  context  = "components/sciget-all"
  target   = "component"
  contexts = { sciget = "target:sciget" }
}

target "sciget-all-test" {
  inherits = ["sciget-all"]
  target   = "test"
  output   = ["type=cacheonly"]
}

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

target "sciget-datascience" {
  inherits = ["_component"]
  context  = "components/sciget-datascience"
  target   = "component"
  contexts = { sciget = "target:sciget" }
}

target "sciget-datascience-test" {
  inherits = ["sciget-datascience"]
  target   = "test"
  output   = ["type=cacheonly"]
}

target "sciget-dermatology" {
  inherits = ["_component"]
  context  = "components/sciget-dermatology"
  target   = "component"
  contexts = { sciget = "target:sciget" }
}

target "sciget-dermatology-test" {
  inherits = ["sciget-dermatology"]
  target   = "test"
  output   = ["type=cacheonly"]
}

target "sciget-preclinical" {
  inherits = ["_component"]
  context  = "components/sciget-preclinical"
  target   = "component"
  contexts = { sciget = "target:sciget" }
}

target "sciget-preclinical-test" {
  inherits = ["sciget-preclinical"]
  target   = "test"
  output   = ["type=cacheonly"]
}

target "sciget-molecular-imaging" {
  inherits = ["_component"]
  context  = "components/sciget-molecular-imaging"
  target   = "component"
  contexts = { sciget = "target:sciget" }
}

target "sciget-molecular-imaging-test" {
  inherits = ["sciget-molecular-imaging"]
  target   = "test"
  output   = ["type=cacheonly"]
}

target "sciget-genomics" {
  inherits = ["_component"]
  context  = "components/sciget-genomics"
  target   = "component"
  contexts = { sciget = "target:sciget" }
}

target "sciget-genomics-test" {
  inherits = ["sciget-genomics"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# The EESSI CVMFS repository (software.eessi.io), Lmod integration, and
# curated desktop app launcher hooks (included in scidesktop for all images).
target "eessi-cvmfs" {
  inherits = ["_component"]
  context  = "components/eessi-cvmfs"
  target   = "component"
  args = {
    EESSI_CVMFS_CONFIG_VERSION = EESSI_CVMFS_CONFIG_VERSION
    EESSI_CVMFS_CONFIG_SHA256  = EESSI_CVMFS_CONFIG_SHA256
  }
}

target "eessi-cvmfs-test" {
  inherits = ["eessi-cvmfs"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# File viewers for JupyterLab (NiiVue and FreeBrowse). Each is a JupyterLab
# extension and a server extension outside the Jupyter environment; their
# builds and tests borrow that environment.
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
    NODE_VERSION      = NODE_VERSION
    FREEBROWSE_COMMIT = FREEBROWSE_COMMIT
  }
}

target "jupyterlab-freebrowse-test" {
  inherits = ["jupyterlab-freebrowse"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: Neuroglancer viewer for OME-Zarr, N5, Precomputed, NIfTI and mesh
# datasets. Copied by microdesktop.
target "jupyterlab-neuroglancer" {
  inherits = ["_component"]
  context  = "components/jupyterlab-neuroglancer"
  target   = "component"
  contexts = {
    jupyter-env      = "target:jupyter-env"
    neuroglancer-src = NEUROGLANCER_SRC
  }
  args = {
    NODE_VERSION        = NODE_VERSION
    NEUROGLANCER_COMMIT = NEUROGLANCER_COMMIT
  }
}

target "jupyterlab-neuroglancer-test" {
  inherits = ["jupyterlab-neuroglancer"]
  target   = "test"
  output   = ["type=cacheonly"]
}

target "micromamba-test" {
  inherits = ["micromamba"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: not in the base. The datadesktop image copies it.
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

# Codex, Claude Code and OpenCode for terminals (included in scidesktop).
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

# The adapters that give Jupyter AI's chat a Codex and a Claude Code persona
# (included in scidesktop). Their test starts them with those agents and the
# Jupyter environment.
target "acp-adapters" {
  inherits = ["_component"]
  context  = "components/acp-adapters"
  target   = "component"
  contexts = {
    code-server   = "target:code-server"
    coding-agents = "target:coding-agents"
    jupyter-env   = "target:jupyter-env"
  }
  args = {
    NODE_VERSION = NODE_VERSION
  }
}

target "acp-adapters-test" {
  inherits = ["acp-adapters"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Google Antigravity ACP server for Gemini models in T3 Code (included in
# scidesktop). Its test runs an ACP initialize handshake using jupyter-env's Python.
target "antigravity-acp" {
  inherits = ["_component"]
  context  = "components/antigravity-acp"
  target   = "component"
  contexts = { jupyter-env = "target:jupyter-env" }
  args = {
    ANTIGRAVITY_ACP_VERSION      = ANTIGRAVITY_ACP_VERSION
    ANTIGRAVITY_ACP_SHA256_AMD64 = ANTIGRAVITY_ACP_SHA256_AMD64
    ANTIGRAVITY_ACP_SHA256_ARM64 = ANTIGRAVITY_ACP_SHA256_ARM64
  }
}

target "antigravity-acp-test" {
  inherits = ["antigravity-acp"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# T3 Code behind the notebook server, as the scigent.ai tile (included in
# scidesktop). Its test runs it through a notebook server, so it borrows the
# Jupyter environment.
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

# T3 Connect for T3 Code (included in scidesktop). Its test runs both through
# a notebook server, so it borrows T3 Code and the Jupyter environment.
target "t3-connect" {
  inherits = ["_component"]
  context  = "components/t3-connect"
  target   = "component"
  contexts = {
    t3-code     = "target:t3-code"
    jupyter-env = "target:jupyter-env"
  }
  args = {
    T3_CLOUDFLARED_VERSION      = T3_CLOUDFLARED_VERSION
    T3_CLOUDFLARED_SHA256_AMD64 = T3_CLOUDFLARED_SHA256_AMD64
    T3_CLOUDFLARED_SHA256_ARM64 = T3_CLOUDFLARED_SHA256_ARM64
  }
}

target "t3-connect-test" {
  inherits = ["t3-connect"]
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

# DataLad and git-annex for terminals, in an isolated venv backed by jupyter-env.
target "datalad" {
  inherits = ["_component"]
  context  = "components/datalad"
  target   = "component"
  contexts = { jupyter-env = "target:jupyter-env" }
}

target "datalad-test" {
  inherits = ["datalad"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Lightcone's lc in an isolated venv backed by jupyter-env, with a compute
# catalog sized to the session's Slurm queue.
target "lightcone" {
  inherits = ["_component"]
  context  = "components/lightcone"
  target   = "component"
  contexts = { jupyter-env = "target:jupyter-env" }
}

target "lightcone-test" {
  inherits = ["lightcone"]
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

# Optional: core scientific VS Code extensions (Python, Jupyter, GitHub PRs,
# CSV, Slurm) in code-server's system extensions folder. Shared across domain
# images with code-server.
target "vscode-core" {
  inherits = ["_component"]
  context  = "components/vscode-core"
  target   = "component"
  contexts = {
    code-server = "target:code-server"
    jupyter-env = "target:jupyter-env"
  }
  args = {
    VSCODE_PYTHON_VERSION      = VSCODE_PYTHON_VERSION
    VSCODE_PYTHON_SHA256_AMD64 = VSCODE_PYTHON_SHA256_AMD64
    VSCODE_PYTHON_SHA256_ARM64 = VSCODE_PYTHON_SHA256_ARM64
    VSCODE_JUPYTER_VERSION     = VSCODE_JUPYTER_VERSION
    VSCODE_JUPYTER_SHA256      = VSCODE_JUPYTER_SHA256
    VSCODE_GITHUB_PR_VERSION   = VSCODE_GITHUB_PR_VERSION
    VSCODE_GITHUB_PR_SHA256    = VSCODE_GITHUB_PR_SHA256
    VSCODE_CSV_VERSION         = VSCODE_CSV_VERSION
    VSCODE_CSV_SHA256          = VSCODE_CSV_SHA256
    VSCODE_SLURM_VERSION       = VSCODE_SLURM_VERSION
    VSCODE_SLURM_SHA256        = VSCODE_SLURM_SHA256
  }
}

target "vscode-core-test" {
  inherits = ["vscode-core"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: the NiiVue VS Code extension for imaging desktops.
target "vscode-niivue" {
  inherits = ["_component"]
  context  = "components/vscode-niivue"
  target   = "component"
  contexts = {
    code-server = "target:code-server"
    jupyter-env = "target:jupyter-env"
  }
  args = {
    VSCODE_NIIVUE_VERSION = VSCODE_NIIVUE_VERSION
    VSCODE_NIIVUE_SHA256  = VSCODE_NIIVUE_SHA256
  }
}

target "vscode-niivue-test" {
  inherits = ["vscode-niivue"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: the Claude Code and Codex VS Code extensions (~1.5 GB together;
# kept separate from vscode-core so images can take vscode-core without them).
target "vscode-coding-agents" {
  inherits = ["_component"]
  context  = "components/vscode-coding-agents"
  target   = "component"
  contexts = {
    code-server   = "target:code-server"
    coding-agents = "target:coding-agents"
    jupyter-env   = "target:jupyter-env"
  }
  args = {
    VSCODE_CLAUDE_CODE_VERSION      = VSCODE_CLAUDE_CODE_VERSION
    VSCODE_CLAUDE_CODE_SHA256_AMD64 = VSCODE_CLAUDE_CODE_SHA256_AMD64
    VSCODE_CLAUDE_CODE_SHA256_ARM64 = VSCODE_CLAUDE_CODE_SHA256_ARM64
    VSCODE_CHATGPT_VERSION          = VSCODE_CHATGPT_VERSION
    VSCODE_CHATGPT_SHA256_AMD64     = VSCODE_CHATGPT_SHA256_AMD64
    VSCODE_CHATGPT_SHA256_ARM64     = VSCODE_CHATGPT_SHA256_ARM64
  }
}

target "vscode-coding-agents-test" {
  inherits = ["vscode-coding-agents"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: the `scigethelpers` command (cite, kernel, check, info). Its test
# runs it with Lmod, the session's Slurm queue and the Jupyter environment's
# Python, so it borrows those three components.
target "scigethelpers-cli" {
  inherits = ["_component"]
  context  = "components/scigethelpers-cli"
  target   = "component"
  contexts = {
    lmod        = "target:lmod"
    slurm       = "target:slurm"
    jupyter-env = "target:jupyter-env"
  }
}

target "scigethelpers-cli-test" {
  inherits = ["scigethelpers-cli"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# VirtualGL for opt-in GPU-accelerated OpenGL rendering via headless EGL
# (included in scidesktop).
target "virtualgl" {
  inherits = ["_component"]
  context  = "components/virtualgl"
  target   = "component"
  args = {
    VIRTUALGL_VERSION      = VIRTUALGL_VERSION
    VIRTUALGL_SHA256_AMD64 = VIRTUALGL_SHA256_AMD64
    VIRTUALGL_SHA256_ARM64 = VIRTUALGL_SHA256_ARM64
  }
}

target "virtualgl-test" {
  inherits = ["virtualgl"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Slurm Queue Manager extension for JupyterLab (included in scidesktop).
target "jupyterlab-slurm" {
  inherits = ["_component"]
  context  = "components/jupyterlab-slurm"
  target   = "component"
  contexts = {
    jupyter-env          = "target:jupyter-env"
    jupyterlab-slurm-src = JUPYTERLAB_SLURM_SRC
  }
  args = {
    NODE_VERSION            = NODE_VERSION
    JUPYTERLAB_SLURM_COMMIT = JUPYTERLAB_SLURM_COMMIT
  }
}

target "jupyterlab-slurm-test" {
  inherits = ["jupyterlab-slurm"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Generic scientific workflow engines: Nextflow, nf-test and Snakemake
# (included in scidesktop).
target "workflow-engines" {
  inherits = ["_component"]
  context  = "components/workflow-engines"
  target   = "component"
  contexts = { jupyter-env = "target:jupyter-env" }
  args = {
    TEMURIN_JRE_VERSION      = TEMURIN_JRE_VERSION
    TEMURIN_JRE_SHA256_AMD64 = TEMURIN_JRE_SHA256_AMD64
    TEMURIN_JRE_SHA256_ARM64 = TEMURIN_JRE_SHA256_ARM64
    NEXTFLOW_VERSION = NEXTFLOW_VERSION
    NEXTFLOW_SHA256  = NEXTFLOW_SHA256
    NF_TEST_VERSION  = NF_TEST_VERSION
    NF_TEST_SHA256   = NF_TEST_SHA256
    VIASH_VERSION    = VIASH_VERSION
    VIASH_SHA256     = VIASH_SHA256
  }
}

target "workflow-engines-test" {
  inherits = ["workflow-engines"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# rclone from conda-forge in /opt/rclone, on PATH. Part of the base image.
target "rclone" {
  inherits = ["_component"]
  context  = "components/rclone"
  target   = "component"
}

target "rclone-test" {
  inherits = ["rclone"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# gh from conda-forge in /opt/gh, on PATH. Part of the base image.
target "gh" {
  inherits = ["_component"]
  context  = "components/gh"
  target   = "component"
}

target "gh-test" {
  inherits = ["gh"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# aria2 from conda-forge in /opt/aria2, on PATH. Part of the base image.
target "aria2" {
  inherits = ["_component"]
  context  = "components/aria2"
  target   = "component"
}

target "aria2-test" {
  inherits = ["aria2"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# tcsh from conda-forge in /opt/tcsh, on PATH. Part of the base image.
target "tcsh" {
  inherits = ["_component"]
  context  = "components/tcsh"
  target   = "component"
}

target "tcsh-test" {
  inherits = ["tcsh"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: microscopy Python analysis kernel (numpy, scipy, scikit-image,
# tifffile, imagecodecs, zarr, ome-zarr, bioio, dask, xarray). Copied by microdesktop.
target "microscopy-env" {
  inherits = ["_component"]
  context  = "components/microscopy-env"
  target   = "component"
}

target "microscopy-env-test" {
  inherits = ["microscopy-env"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: general Data Science Python kernel (numpy, scipy, pandas, polars,
# pyarrow, duckdb, jupysql, scikit-learn, statsmodels, xgboost, lightgbm,
# optuna, shap, plotly, altair, sqlalchemy). Copied by datadesktop.
target "datascience-env" {
  inherits = ["_component"]
  context  = "components/datascience-env"
  target   = "component"
}

target "datascience-env-test" {
  inherits = ["datascience-env"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: dermatology Python analysis kernel (numpy, scipy, scikit-image,
# scikit-learn, statsmodels, tifffile, imagecodecs, zarr, ome-zarr, bioio,
# openslide, pydicom, colour-science, trimesh, dask, xarray). Copied by dermdesktop.
target "dermatology-env" {
  inherits = ["_component"]
  context  = "components/dermatology-env"
  target   = "component"
}

target "dermatology-env-test" {
  inherits = ["dermatology-env"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: preclinical imaging Python analysis kernel (numpy, scipy,
# scikit-image, scikit-learn, statsmodels, tifffile, zarr, pydicom, SimpleITK,
# nibabel, nilearn, ipyniivue, brkraw, dask, xarray). Copied by preclinicaldesktop.
target "preclinical-env" {
  inherits = ["_component"]
  context  = "components/preclinical-env"
  target   = "component"
}

target "preclinical-env-test" {
  inherits = ["preclinical-env"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: molecular imaging Python analysis kernel (numpy, scipy,
# scikit-image, scikit-learn, statsmodels, pydicom, highdicom, SimpleITK,
# nibabel, nilearn, ipyniivue). Copied by moleculardesktop.
target "molecular-imaging-env" {
  inherits = ["_component"]
  context  = "components/molecular-imaging-env"
  target   = "component"
}

target "molecular-imaging-env-test" {
  inherits = ["molecular-imaging-env"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: curated Viash Hub & OpenPipelines workflow catalog and `viash-catalog`
# CLI for workflow discovery, rootless Apptainer/Slurm Nextflow commands, and
# Viash component scaffolding. Copied by genomicsdesktop.
target "viash-hub" {
  inherits = ["_component"]
  context  = "components/viash-hub"
  target   = "component"
  contexts = {
    workflow-engines = "target:workflow-engines"
    jupyter-env      = "target:jupyter-env"
  }
}

target "viash-hub-test" {
  inherits = ["viash-hub"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: genomics and single-cell Python analysis kernel (anndata, scanpy,
# mudata, biopython, polars, pyarrow, h5py, zarr, dask, xarray, igraph,
# leidenalg, umap-learn, pyyaml, jsonschema, nf-core) + EESSI genomics metadata.
# Copied by genomicsdesktop.
target "genomics-env" {
  inherits = ["_component"]
  context  = "components/genomics-env"
  target   = "component"
}

target "genomics-env-test" {
  inherits = ["genomics-env"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: coding-agent instructions for genomicsdesktop (Viash Hub,
# OpenPipelines, rootless Apptainer Nextflow profiles, EESSI genomics modules).
# Copied by genomicsdesktop.
target "genomics-agents" {
  inherits = ["_component"]
  context  = "components/genomics-agents"
  target   = "component"
  contexts = {
    coding-agents = "target:coding-agents"
    startup       = "target:startup"
  }
}

target "genomics-agents-test" {
  inherits = ["genomics-agents"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: neuroimaging Python analysis kernel (nibabel, nipype, niwrap,
# pydra, nipoppy, ipyniivue, datalad, xnat, nf-core). Copied by neurodesktop.
target "neuroimaging-env" {
  inherits = ["_component"]
  context  = "components/neuroimaging-env"
  target   = "component"
  contexts = {
    jupyter-env = "target:jupyter-env"
  }
}

target "neuroimaging-env-test" {
  inherits = ["neuroimaging-env"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# Optional: Neurodesk neuroimaging compatibility layer (FreeSurfer env
# defaults, nf-neuro modules, local container module discovery, getting-started
# notebook). Copied by neurodesktop.
target "neurodesk-compat" {
  inherits = ["_component"]
  context  = "components/neurodesk-compat"
  target   = "component"
  contexts = {
    nf-neuro-src = NF_NEURO_MODULES_SRC
  }
  args = {
    NF_NEURO_MODULES_COMMIT = NF_NEURO_MODULES_COMMIT
  }
}

target "neurodesk-compat-test" {
  inherits = ["neurodesk-compat"]
  target   = "test"
  output   = ["type=cacheonly"]
}

# --- Images -----------------------------------------------------------------

# The base: the components assembled on the OS layer.
target "scidesktop" {
  inherits = ["_common"]
  context  = "images/scidesktop"
  contexts = {
    os                    = "target:os-ubuntu"
    startup               = "target:startup"
    jupyter-env           = "target:jupyter-env"
    selkies               = "target:selkies"
    apptainer             = "target:apptainer"
    lmod                  = "target:lmod"
    sciget                = "target:sciget"
    slurm                 = "target:slurm"
    virtualgl             = "target:virtualgl"
    datalad               = "target:datalad"
    code-server           = "target:code-server"
    vscode-core           = "target:vscode-core"
    scigethelpers-cli     = "target:scigethelpers-cli"
    jupyterlab-slurm      = "target:jupyterlab-slurm"
    workflow-engines      = "target:workflow-engines"
    lightcone             = "target:lightcone"
    sciget-all            = "target:sciget-all"
    eessi-cvmfs           = "target:eessi-cvmfs"
    coding-agents         = "target:coding-agents"
    acp-adapters          = "target:acp-adapters"
    antigravity-acp       = "target:antigravity-acp"
    t3-code               = "target:t3-code"
    t3-connect            = "target:t3-connect"
    rclone                = "target:rclone"
    gh                    = "target:gh"
    aria2                 = "target:aria2"
    tcsh                  = "target:tcsh"
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
    scidesktop-base         = "target:scidesktop"
    sciget-microscopy       = "target:sciget-microscopy"
    jupyterlab-neuroglancer = "target:jupyterlab-neuroglancer"
    microscopy-env          = "target:microscopy-env"
  }
  tags   = [MICRODESKTOP_IMAGE]
  output = ["type=docker"]
}

target "datadesktop" {
  inherits = ["_common"]
  context  = "images/datadesktop"
  contexts = {
    scidesktop-base    = "target:scidesktop"
    sciget-datascience = "target:sciget-datascience"
    datascience-env    = "target:datascience-env"
    ai-ready           = "target:ai-ready"
  }
  tags   = [DATADESKTOP_IMAGE]
  output = ["type=docker"]
}

target "dermdesktop" {
  inherits = ["_common"]
  context  = "images/dermdesktop"
  contexts = {
    scidesktop-base         = "target:scidesktop"
    sciget-dermatology      = "target:sciget-dermatology"
    jupyterlab-neuroglancer = "target:jupyterlab-neuroglancer"
    dermatology-env         = "target:dermatology-env"
  }
  tags   = [DERMDESKTOP_IMAGE]
  output = ["type=docker"]
}

target "preclinicaldesktop" {
  inherits = ["_common"]
  context  = "images/preclinicaldesktop"
  contexts = {
    scidesktop-base    = "target:scidesktop"
    sciget-preclinical = "target:sciget-preclinical"
    vscode-niivue      = "target:vscode-niivue"
    jupyterlab-niivue  = "target:jupyterlab-niivue"
    preclinical-env    = "target:preclinical-env"
  }
  tags   = [PRECLINICALDESKTOP_IMAGE]
  output = ["type=docker"]
}

target "moleculardesktop" {
  inherits = ["_common"]
  context  = "images/moleculardesktop"
  contexts = {
    scidesktop-base          = "target:scidesktop"
    sciget-molecular-imaging = "target:sciget-molecular-imaging"
    vscode-niivue            = "target:vscode-niivue"
    jupyterlab-niivue        = "target:jupyterlab-niivue"
    molecular-imaging-env    = "target:molecular-imaging-env"
  }
  tags   = [MOLECULARDESKTOP_IMAGE]
  output = ["type=docker"]
}

target "genomicsdesktop" {
  inherits = ["_common"]
  context  = "images/genomicsdesktop"
  contexts = {
    scidesktop-base = "target:scidesktop"
    sciget-genomics = "target:sciget-genomics"
    viash-hub       = "target:viash-hub"
    genomics-env    = "target:genomics-env"
    genomics-agents = "target:genomics-agents"
  }
  tags   = [GENOMICSDESKTOP_IMAGE]
  output = ["type=docker"]
}

# scidesktop for neuroimaging: what neurodesk/neurodesktop gives its users,
# from components (docs/neurodesktop.md).
target "neurodesktop" {
  inherits = ["_common"]
  context  = "images/neurodesktop"
  contexts = {
    scidesktop-base      = "target:scidesktop"
    sciget-neuroimaging  = "target:sciget-neuroimaging"
    neurodesk-cvmfs      = "target:neurodesk-cvmfs"
    vscode-niivue        = "target:vscode-niivue"
    vscode-coding-agents  = "target:vscode-coding-agents"
    jupyterlab-niivue     = "target:jupyterlab-niivue"
    jupyterlab-freebrowse = "target:jupyterlab-freebrowse"
    neurodesk-agents      = "target:neurodesk-agents"
    neuroimaging-env     = "target:neuroimaging-env"
    neurodesk-compat     = "target:neurodesk-compat"
  }
  tags   = [NEURODESKTOP_IMAGE]
  output = ["type=docker"]
}
