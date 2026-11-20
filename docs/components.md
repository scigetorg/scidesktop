# Components: how the image is built

scidesktop is assembled from **components**. Each component is a folder under
`components/` that builds one part of the image on its own, with its own test.
The base image's `images/scidesktop/Dockerfile` only stacks the components' outputs onto the OS layer and sets
image metadata. `docker-bake.hcl` wires the components together and holds every
version. Domain images build on the base; see [images.md](images.md).

```
docker buildx bake                             # every image
docker buildx bake test                        # every component's test
docker buildx bake apptainer-test              # one component's test
python3 test/contract.py static                # the rules below, before building
python3 test/contract.py layers                # the rules below, after building
./test/image-smoke.sh scidesktop               # the assembled image end to end
```

CI runs all of these on every pull request, once on amd64 and once on arm64.
A pull request that breaks a rule fails with the rule's code (S1-S8, L1-L5, I1)
and what to change.

## The rules

### Where things go

1. **Everything that can be a component is a component.** Software that installs into its
   own folder (a prefix such as `/opt/apptainer`) is a component, with the files
   that wire it in: startup hooks, command links, shell setup, its Jupyter
   config, its manifest entry.
2. **Distribution packages go in the OS component.** Anything installed with apt
   (spread across `/usr`, integrated with the system, updated by the weekly
   package snapshot) is listed in `components/os-ubuntu/packages/*.txt`.
3. **Python packages for Jupyter go in `jupyter-env`.** There is one Jupyter
   environment; extensions are packages in its `environment.yml`.
4. **The base Dockerfile only assembles (S1, S2).** It may contain `FROM os`,
   one `COPY --link --from=<component> / /` per component, and image metadata (`ENV`,
   `LABEL`, `EXPOSE`, `HEALTHCHECK`, `ENTRYPOINT`, `CMD`, `WORKDIR`, `USER`).
   No `RUN`, no other `COPY`. Environment variables stay here because they are
   image configuration, not files; comment which component each belongs to.

### What a component looks like

```
components/<component>/
  Dockerfile        stages: build (optional), rootfs, component, test
  rootfs/           integration files at their image paths (hooks, links, config)
  ...               anything the build needs (lock files, patches)
```

- **`component` stage, `FROM scratch` (S3):** only the files the component adds to the
  image, at their final paths. The assembly copies it whole.
- **`rootfs` stage:** copies `rootfs/` and removes group and other write
  permission, so the result does not depend on the checkout's umask.
- **`test` stage (S3):** `FROM os`, copies the component in, and checks it works on
  its own. Add a `<component>-test` target to the bake group `test`.
- **`test/<component>-smoke.sh` (optional):** end-to-end checks of the
  component in an assembled image, taking the image as its argument.
  `test/image-smoke.sh` runs it on every image that holds the component.
- **Manifest entry (L4):** the component writes `/opt/scidesktop/manifest.d/<component>.json`
  with its versions, detected from what was built.
- **Build `FROM ${UBUNTU_IMAGE}`** (plain Ubuntu of the OS layer's release) and
  install build dependencies there, even when compiling against OS libraries:
  the same release has the same ABI, and OS package updates (snapshot bumps)
  then neither rebuild the component nor change its layer. The test stage runs
  it on the real OS layer and catches any missing library. `os-build` (the
  snapshot OS) is there only for a component that needs the exact OS packages
  at build time.

### Versions

- **One copy of each version (S4, S5).** Versions, digests and checksums live
  in the Versions section of `docker-bake.hcl`, one variable per line, with a
  `# renovate:` comment above it. Component Dockerfiles declare `ARG NAME` without a
  value; each bake target passes only the ones its component uses. A missing value
  fails the build (`${NAME:?}` in `RUN`).
- **Python pins** live in the component's `environment.yml` or `requirements.in`;
  run the component's `./lock` after changing one. They stay out of the bake
  file on purpose: the build installs only from the lock file (every package,
  exact URL and hash), which `./lock` solves from those files before the build.
  Passing versions from bake would mean solving during the build, so dependency
  versions would drift between builds; generating `environment.yml` from bake
  would add templating for the few top-level pins only, while the lock file
  stays the record of everything installed.
- **Checksums** are not updated by Renovate: update the `*_SHA256` variable
  with its version. A file that differs per architecture has one variable per
  architecture, `NAME_SHA256_AMD64` and `NAME_SHA256_ARM64` (S5); update both.

### Architectures

Every image is built for amd64 and arm64. One bake run builds one platform:
the machine's own by default, or `PLATFORM=linux/arm64 docker buildx bake`.
CI builds each on a runner of that architecture and joins the two when it
publishes (see [images.md](images.md#ci-and-publishing)).

- **Ask `components/target-arch`, not the machine (S7).** buildx sets
  `TARGETARCH` (`amd64`, `arm64`). `target-arch <naming>` turns it into the
  name an upstream uses: `conda` (`linux-64`, `linux-aarch64`), `uname`
  (`x86_64`, `aarch64`), `node` (`x64`, `arm64`), `deb`, `go`. It fails with a clear message on an
  architecture scidesktop has no build for. A component declares
  `ARG TARGETARCH` and mounts the helper into the `RUN` that needs it:

  ```dockerfile
  ARG TARGETARCH
  RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
      curl -fsSLO "https://example.org/tool-$(target-arch uname).tar.gz"
  ```

  Nothing calls `uname -m` or `dpkg --print-architecture`. A new naming is a
  line in `target-arch`; a new architecture is a line there, a CI runner, and
  whatever the build then reports missing.
- **A checksum per architecture**, picked by `TARGETARCH`; see
  `components/micromamba/Dockerfile`.
- **A conda lock per architecture (S7).** `./lock` solves `environment.yml`
  for every architecture in one run and writes `linux-64.lock` and
  `linux-aarch64.lock`; the build installs the one for its `TARGETARCH`, and
  fails if a pin is missing from either. The pip lock (`requirements.lock`) is
  one file for all architectures: each pin lists the hashes of every file of
  that version, so `--require-hashes` installs exactly the locked version
  whichever wheel fits.
- **Software without an arm64 build** cannot be in an image. Build it from
  source in the component, or leave it to sciget and Apptainer.

### Shared places

Components meet in a few shared folders. Each file in them has one owner.

| Place | Use | Naming |
| --- | --- | --- |
| `/usr/local/bin/before-notebook.d/` | startup hooks, run in name order by docker-stacks | `NN-<component>`: two-digit order, then the component name |
| `/usr/local/bin/` | command links into the component's prefix | the command's own name |
| `/etc/profile.d/` | login shell setup | `<component>.sh` or the upstream name |
| `/etc/bash.bashrc.d/` | interactive shell setup (all bash terminals) | `<component>.sh` |
| `/etc/jupyter/` | Jupyter server settings, the lowest-priority config folder | `jupyter_server_config.py` is startup's (docker-stacks); `jupyter_server_config.json` is jupyter-env's |
| `/etc/scidesktop/jupyter_server_config.d/` | a component's part of the notebook server's configuration: launcher tiles, proxied services, handlers (S8) | `<component>.py`; it adds to shared settings (`c.ServerProxy.servers.update(...)`) and never assigns them |
| `/usr/local/etc/jupyter/` | the loader of those parts, and server extension switches | `jupyter_server_config.py` is jupyter-env's and only loads the parts; `jupyter_server_config.d/<component>.json` only enables server extensions (Jupyter ignores other settings there) |
| `/usr/local/share/jupyter/kernels/` | notebook kernels from components outside the Jupyter environment | `<component>/` |
| `/opt/scidesktop/` | scidesktop's own scripts; `manifest.d/<component>.json` | `<component>.json` |
| `/etc/scidesktop/home-defaults/` | files copied into each user's home at start, never overwriting the user's own (derived images' default settings) | the path the file should have in the home |

The layer check enforces what it can:

The layer rules cover the base's components and those a domain image copies.

- **L1:** no file is written by two components.
- **L2:** no component file shadows a file in the OS layer.
- **L3:** a folder a component creates must have the same mode and owner as the
  existing one. A linked layer silently replaces the folder's permissions
  otherwise; this is how `/usr/local/share` once became unreadable.
- **L4:** each component has a valid manifest entry.
- **L5:** nothing root-owned is writable by group or others.

What no check can see (two components setting the same option in different
files, or hooks depending on an order) is covered by the naming above, one
owner per setting, and the smoke test.

### Jupyter configuration (S8)

Every component registers with the notebook server the same way, whether it is
in the base (the desktop) or optional (AI Ready, T3 Code): it ships
`/etc/scidesktop/jupyter_server_config.d/<component>.py`. jupyter-env's
`/usr/local/etc/jupyter/jupyter_server_config.py` loads those files in name
order. Jupyter reads that folder after `/etc/jupyter` and before the user's
`~/.jupyter`, so users keep the last word.

A part adds to shared settings and never assigns them:

```python
c.ServerProxy.servers.update({"mytool": {...}})   # not: c.ServerProxy.servers = {...}
```

so the parts do not depend on their order. Kernels go to
`/usr/local/share/jupyter/kernels/<component>`, where Jupyter looks without
being told.

An image that copies a component therefore sets nothing for it. Rule S8 checks
the three ways this used to go wrong: a part with another name, a part that
assigns `c.ServerProxy.servers`, and an image `ENV` with `JUPYTER_CONFIG_PATH`
or `JUPYTER_PATH`.

### What an image holds (I1)

`python3 test/contract.py image <image> [ref]` checks a built image against its
bake target: it has the manifest entry of every component the target (or the
image it is `FROM`) copies, and no manifest entry, prefix (`/opt/<component>`)
or `rootfs/` file of any other component. This is the check that keeps
optional components out of the base. `test/image-smoke.sh` runs it first.

### Order and layers

The assembly copies components from least to most frequently changed. Each `COPY
--link` layer depends only on its own component, so updating one component leaves every
other component's layer identical; nodes download only what changed. Keep new components
in that order.

## Adding a component

1. `components/<component>/Dockerfile` with `rootfs`, `component` and `test` stages (copy
   an existing component, e.g. `components/lmod`), and `rootfs/` for its integration files.
2. Versions in `docker-bake.hcl` with `# renovate:` comments; targets `<component>`
   and `<component>-test`; add `<component>-test` to group `test`. CI finds
   the component by its folder: nothing to add to the workflows.
3. If it goes into the image: add it to the `scidesktop` target's contexts and
   one `COPY --link --from=<component> / /` line to `images/scidesktop/Dockerfile`.
   If only some images want it (an optional component, see
   [images.md](images.md#optional-components)): add the context and the `COPY`
   line to those images instead. Nothing else: its Jupyter part, kernels,
   hooks and smoke test come with it.
4. A Renovate group for `components/<component>/**` and its dependency names.
5. `python3 test/contract.py static`, build, `python3 test/contract.py layers`,
   `./test/image-smoke.sh <image>`.
