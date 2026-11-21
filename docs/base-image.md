# Base image design

Status: agreed 2026-11-15; first implementation built 2026-11-16 (see
`docs/overnight-2026-11-16.md`). Target: the Kubernetes MVP. Replaces `quay.io/jupyter/base-notebook` with a
base we build ourselves. Ubuntu 26.04 LTS ships first, on amd64 and arm64;
the layout is built so that another distribution or CPU architecture is an
addition, not a rewrite.

## Goals

- Own the startup path, the Python environment and every installed package.
- One Python environment we maintain (Jupyter's). The OS layer has no system
  `python3`.
- Reproducible OS packages from a pinned base digest plus a package snapshot.
- Keep docker-stacks' runtime contract so JupyterHub, operators and users see
  no change.
- Adding an OS or architecture touches one layer and one support table.

## Non-goals

- Hardened or distroless bases. A full desktop on top erases their benefit;
  security comes from CI scanning, SBOMs, provenance and signing instead.
- Shipping anything other than Ubuntu 26.04 for the MVP. A RHEL-family
  variant and Selkies 2.3.0 are deferred, but the layout must not block them.

## Layers

```
┌───────────────────────────────────────────────┐
│ 3. image       config, hooks, labels, USER     │  OS-neutral
├───────────────────────────────────────────────┤
│ 2. common      startup scripts, micromamba +   │  OS-neutral
│                Jupyter env, Selkies, sciget    │
├───────────────────────────────────────────────┤
│ 1. os-<id>     packages, repo pinning, user,   │  one per OS
│                locale, tini                    │
├───────────────────────────────────────────────┤
│ 0. distro base image, digest-pinned            │
└───────────────────────────────────────────────┘
```

Each layer may rely only on the contract of the layer below, never on how it
was built.

### Selecting the OS

One Dockerfile. Each OS gets a stage named `os-<id>`; a build ARG picks one,
and BuildKit builds only the stages the final image references:

```dockerfile
ARG OS=ubuntu26.04
FROM ubuntu@sha256:…        AS os-ubuntu26.04
RUN /build/os/ubuntu/install
# FROM rockylinux@sha256:… AS os-rocky10   (future)
FROM os-${OS} AS os
FROM os AS common
…
```

### Selecting the architecture

Builds use buildx's `TARGETARCH`. Nothing calls
`dpkg --print-architecture` or `uname -m` directly. One helper,
`components/target-arch`, lists the supported architectures (amd64, arm64),
maps `TARGETARCH` to each upstream's naming (`linux-64`/`linux-aarch64`,
`x86_64`/`aarch64`) and fails clearly on any other. Files that differ per
architecture have a checksum or a lock for each. The rules are in
[components.md](components.md#architectures).

One bake run builds one platform (`PLATFORM`, the machine's own by default).
CI builds each architecture on a runner of that architecture, without
emulation, and joins the results into one multi-arch image only after both
pass ([images.md](images.md#ci-and-publishing)).

## Repository layout

```
components/
  os-ubuntu/          Dockerfile, packages/<capability>.txt, snapshot, test
  apptainer/          Dockerfile, test
  jupyter-env/        Dockerfile, environment.yml, a lock per arch, test
  selkies/            Dockerfile, test
  lmod/               Dockerfile, test
  startup/            vendored docker-stacks scripts + LICENSE, test
  target-arch         supported arches; TARGETARCH → upstream names
config/               runtime config and hooks (exists today)
docker-bake.hcl       component targets + images
images/scidesktop/    the assembly (Dockerfile); domain images beside it
test/
  os-contract.sh      asserts the OS layer's contract
  smoke.sh            exists; runs against the assembled image
```

A future OS adds `components/os-<id>/` with the same capability file names.

## Layer 1 contract (what every `os-<id>` must provide)

Expressed as capabilities. Each OS directory has a package list per
capability using that distro's package names, and `test/os-contract.sh`
checks the result by behaviour (binaries, libraries, users), not by package
name.

| Capability | Must provide |
| --- | --- |
| `core` | bash, coreutils, sudo, ca-certificates, curl, shadow-utils (`usermod`, `groupmod`), tini |
| `locale` | `LANG=C.UTF-8` works, `en_US.UTF-8` generated |
| `user` | `jovyan` UID 1000, group `users` GID 100, home `/home/jovyan` |
| `x11` | Xvfb, xrandr, xdpyinfo, xkb tools, libX11/xcb/Xtst/Xfixes/Xdamage |
| `gl` | libGL, libEGL, libGLES, libglvnd, libdrm, libva (pixelflux links it) |
| `desktop` | IceWM session, Thunar, xfce4-terminal, an icon theme, dbus-x11 |
| `audio` | PipeWire, pipewire-pulse, WirePlumber, libpulse |
| `fuse` | fuse3, squashfuse, fuse-overlayfs, uidmap, fakeroot |
| `cvmfs` | CVMFS client, `cvmfs-config-none` |
| `lmod` | Lmod runtime (Lua 5.4 + posix + filesystem, tcl) |
| `pinning` | a recorded mechanism that reproduces this package set |

`pinning` differs per OS: Ubuntu uses `snapshot.ubuntu.com` at a dated
timestamp, then restores live sources for runtime `apt`. A RHEL-family OS would
pin a point release from its vault repos, plus `dnf versionlock`. Whatever the
mechanism, the build must be reproducible from the Dockerfile alone.

## Layer 2: common

Installed only through mechanisms that don't depend on the distro, so it needs
no per-OS work:

| Component | Delivery | Arches available upstream |
| --- | --- | --- |
| micromamba | static binary | amd64, arm64, ppc64le, riscv64 |
| Jupyter environment | conda-forge via `components/jupyter-env/environment.yml` and its lockfile | follows conda-forge |
| Selkies 2.2.1 | manylinux wheel into its own prefix (pixelflux, pcmflux: `manylinux_2_28` wheels) | amd64, arm64 |
| Selkies 2.3.0 (later) | static binary / `.whl` | amd64, arm64 |
| sciget | `COPY --from` the sciget image | its image's platforms |
| startup scripts | `vendor/docker-stacks`, pinned commit | any |

### Jupyter environment

Lives at `/opt/conda`, owned by `jovyan`, so `mamba install` and
`environment.yml` behave as they do on docker-stacks. Contents are limited to
what the image needs: `python`, `jupyterlab`, `jupyterhub-singleuser`,
`jupyter-server-proxy`, `ipykernel`, `mamba`. `nbclassic`, Notebook 7 and
`conda` itself are left out (decided: mamba only). Renovate tracks
`environment.yml`.

### Startup scripts

Copied unchanged from a pinned docker-stacks commit first, then trimmed in
separate, reviewable commits once startup timing shows what costs time.
`ENTRYPOINT ["tini", "-g", "--", "start.sh"]` and
`CMD ["start-notebook.py"]` stay identical, as do `NB_USER`, `NB_UID`,
`NB_GID`, `GRANT_SUDO`, `CHOWN_HOME` and `before-notebook.d` /
`start-notebook.d`. The conda activation hook replacement becomes our own
`before-notebook.d` entry rather than an override.

## Build components and assembly

scidesktop is an assembly of independently built, tested and updated components.
Each component installs into its own prefix and the final image copies the
prefixes in.

| Component | Prefix | Built per | Updated by |
| --- | --- | --- | --- |
| `os-<id>` | the root filesystem | OS × arch | Renovate (base digest), snapshot bot (`apt-snapshot.yml`) |
| `apptainer` | `/opt/apptainer` | OS × arch (source, `FROM os`) | Renovate |
| `jupyter-env` | `/opt/conda` | arch (lockfile; built on the plain Ubuntu image, not `os`) | Renovate (`environment.yml`), then `./lock` |
| `selkies` | `/opt/selkies` | arch (locks; built on the plain Ubuntu image, not `os`) | Renovate (`requirements.in`), then `./lock` |
| `lmod` | `/opt/apps` | OS × arch (needs the OS's Lua) | Renovate |
| `sciget` | `/usr/local/bin/sciget` | arch (static) | Renovate (sciget image digest) |
| `startup` | `/usr/local/bin` | once | Renovate (docker-stacks commit) |

What stays in `os-<id>` as distro packages: anything wired into system paths,
dbus or fontconfig, or with hundreds of shared libraries. That is the desktop
(IceWM, Thunar, Xvfb, Mesa), audio (PipeWire), FUSE and CVMFS. These are reproducible
through the OS layer's `pinning` mechanism, not through separate components.

Rule for a new component: it installs into its own prefix, and is either static,
brings its own libraries (conda-forge, manylinux wheel), or is built `FROM os`.
Never copy a dynamically linked binary between distributions.

### Layout and tooling

```
components/<component>/
  Dockerfile      builds the component; final stage holds only the prefix
  test            runs inside the component's image
docker-bake.hcl   one target per component, plus the images
images/scidesktop/Dockerfile   the assembly: FROM os, COPY --link --from each component
```

`docker buildx bake` builds the components in parallel and passes them to the
assembly as named contexts. Locally that is a single command; in CI each component
is its own job with its own test.

### Update flow

1. A bot bumps a component's pin (package version, base digest, snapshot date).
2. Only that component rebuilds and runs its own test.
3. The assembly rebuilds and the full smoke test runs. This is the gate:
   components that pass alone can still break together.
4. An OS bump fans out only to the components built per OS (`os-<id>`, `lmod`);
   conda-forge, wheel and static components are untouched.

Renovate groups each component's updates under its own label, so the dependency
dashboard shows the state of every component in parallel.

### Staging

- **MVP:** components live in this repo under `components/`, built with bake.
  This gives parallel builds, per-component tests and per-component Renovate pins
  straight away.
- **Later:** publish each component as its own image with its own pipeline; the
  assembly pins component digests. This is a CI change, not a restructure. A component
  that other projects reuse (neurodesktop) can move to its own repo, as
  sciget has.

## Components that need a per-OS decision

| Component | Today | Options |
| --- | --- | --- |
| Apptainer | built from source on Debian bookworm, copied in | **Revised 2026-11-16: source build `FROM os`, `--with-suid`.** conda-forge builds `--without-suid` (checked in its feedstock), which would remove the setuid fallback `config/startup/10-apptainer` relies on. Revisit if the image commits to user namespaces only. |
| Lmod | 9.3 built from source on Ubuntu 24.04 | **Decided: latest release (9.4.5) from source**, in a stage `FROM os`. The archive has 8.7.60; conda-forge's is stale and amd64-only. |
| CVMFS | CERN `.deb` per arch | CERN publishes `.deb` and `.rpm` for amd64 and arm64 |

Rule: **never copy a dynamically linked binary built on one distro into
another**. The current Apptainer stage (glibc 2.36) works on Ubuntu but would
break on EL9 (glibc 2.34). Build against `os`, or use a static or conda-forge
artefact.

## OS-neutral rules for scripts and tests

Everything in layers 2 and 3, and every runtime script:

- No `apt`, `dpkg`, `dnf` or `rpm` calls.
- No Debian-only paths. Today's offenders:
  `/usr/local/lib/python3*/dist-packages/selkies` in `Dockerfile:168` and
  `test/smoke.sh:77`. They go away when Selkies moves into its own prefix.
- No multiarch library paths (`/usr/lib/x86_64-linux-gnu`); use `ldconfig -p`
  if a library has to be found.
- Shell config through `/etc/profile.d`, which both families read.

## Support matrix

`components/target-arch` lists the architectures that are built. The build
matrix in `.github/workflows/image.yml` has one runner per architecture, and
the contract test (S7) keeps the two lists equal.

| | amd64 | arm64 | ppc64le |
| --- | --- | --- | --- |
| ubuntu26.04 | built, published | built, published | blocked: Selkies has no wheel |
| rocky10 | future | future | blocked: Selkies |

Per component on arm64: the OS packages come from the same snapshot (the
snapshot service has every architecture under `/ubuntu`), CVMFS from CERN's
arm64 packages, Apptainer, Lmod and sciget are compiled on the arm64 runner,
and the conda environments and Selkies install from their arm64 locks and
wheels.

## Tags and labels

- Today: `ghcr.io/scigetorg/scidesktop:<short sha>`, `:<YYYY-MM-DD>` and
  `:latest`, each one multi-arch image for amd64 and arm64.
- With a second OS: `:<version>-<os>`, a multi-arch manifest per OS;
  `:<version>` and `:latest` point at the default OS (Ubuntu).
- Labels: `org.scidesktop.os=<id>`, alongside the existing
  `org.scidesktop.desktop_adapter`.

Derived images (microscopydesktop) choose an OS by tag. They should add
software through sciget, conda-forge or Apptainer rather than the distro
package manager, so they stay portable; where they must use the package
manager, they follow the same capability-file pattern.

## Testing

- `test/os-contract.sh` runs at the end of layer 1 during the build and again
  in the smoke test.
- `test/smoke.sh` runs unchanged on amd64 and arm64, and against every future
  matrix cell.
- New: a JupyterHub spawn check (`start-singleuser.py` with Hub env vars),
  replacing the compatibility testing docker-stacks did for us.
- Startup timing breakdown recorded per build, so trimming `start.sh` is
  measured, not guessed.

## Migration order

1. Land Selkies 2.2.1 on the current base. Done.
2. Startup timing baseline on the current image. Done (`test/startup-time.sh`).
3. Components under `components/`, `docker-bake.hcl` and the new assembly; build
   alongside the old Dockerfile until the smoke test passes. Done: passes the
   same 23 of 24 checks as the old image.
4. `test/os-contract.sh` and component tests. Done, with JupyterHub single-user
   checks in the smoke test against a stand-in Hub.
5. Switch over: the assembly becomes `Dockerfile`; delete the old Selkies
   config (`constraints.txt`), the old Renovate entries and the old CI build
   command. Done; CI builds with bake and a per-component GitHub Actions cache.
6. Trim `start.sh` against the timing data. Not needed: it costs 0.02-0.09 s.
   Startup time went to Jupyter's imports instead (rfc3987 patch).
7. LXQt `-dev` packages: not an issue on 26.04 (`lxqt-core` pulls none).

## Open questions

- Is any site already asking for a RHEL-family image? That decides when
  `os-rocky10` moves from future to planned.
