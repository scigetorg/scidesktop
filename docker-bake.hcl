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
# its checksum is updated too.

# renovate: datasource=docker depName=ubuntu
variable "UBUNTU" { default = "26.04@sha256:065aa8626841f16057b78b027b464cd59c4fac36c204c72dcbf48d66f5fa8a96" }
# Ubuntu archive snapshot; moved weekly by .github/workflows/apt-snapshot.yml.
variable "APT_SNAPSHOT" { default = "20261123T000000Z" }
# renovate: datasource=github-releases depName=cvmfs/cvmfs extractVersion=^cvmfs-(?<version>.*)$
variable "CVMFS_VERSION" { default = "2.13.3" }
variable "CVMFS_CONFIG_VERSION" { default = "1.1-0" }

# renovate: datasource=github-releases depName=mamba-org/micromamba-releases
variable "MICROMAMBA_VERSION" { default = "2.10.0-0" }
variable "MICROMAMBA_SHA256" { default = "701f39c06f8e6a670a0e186c8479b9e5c0502a2f0cda6cef65d83bdd2875e8bd" }

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

# The notebook user, set in the OS layer and used by components that own files.
variable "NB_USER" { default = "jovyan" }
variable "NB_UID" { default = "1000" }
variable "NB_GID" { default = "100" }

# --- Build settings ---------------------------------------------------------

variable "IMAGE" { default = "scidesktop:latest" }
variable "MICRODESKTOP_IMAGE" { default = "microdesktop:latest" }
# sciget is built from source at this commit until it publishes an image
# (Renovate tracks its main branch). For local sciget development, build your
# working copy instead: SCIGET_SRC=../sciget docker buildx bake --allow=fs.read=..
variable "SCIGET_COMMIT" { default = "56c2f310188ad60f58ded74f811bd3e889c19882" }
variable "SCIGET_SRC" { default = "https://github.com/scigetorg/sciget.git#${SCIGET_COMMIT}" }

# Every image in images/; building one builds the images it is FROM.
group "default" {
  targets = ["scidesktop", "microdesktop"]
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
    "micromamba-test",
  ]
}

target "_common" {
  platforms = ["linux/amd64"]
}

# --- OS layer ---------------------------------------------------------------

# The runtime OS layer the image is assembled on.
target "os-ubuntu" {
  inherits = ["_common"]
  context  = "components/os-ubuntu"
  target   = "os"
  contexts = { tests = "test" }
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
  contexts = { os = "target:os-ubuntu" }
  context  = "components/micromamba"
  target   = "component"
  args = {
    MICROMAMBA_VERSION = MICROMAMBA_VERSION
    MICROMAMBA_SHA256  = MICROMAMBA_SHA256
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

target "micromamba-test" {
  inherits = ["micromamba"]
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
  }
  tags   = [IMAGE]
  output = ["type=docker"]
}

# Domain images build FROM the base by name. The named context hands them the
# scidesktop target built here, so no registry is involved (docs/images.md).
target "microdesktop" {
  inherits = ["_common"]
  context  = "images/microdesktop"
  contexts = { scidesktop-base = "target:scidesktop" }
  tags     = [MICRODESKTOP_IMAGE]
  output   = ["type=docker"]
}
