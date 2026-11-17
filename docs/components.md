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
./test/smoke.sh scidesktop                     # the assembled image end to end
```

CI runs all of these on every pull request. A pull request that breaks a rule
fails with the rule's code (S1-S5, L1-L5) and what to change.

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
  with its version.

### Shared places

Components meet in a few shared folders. Each file in them has one owner.

| Place | Use | Naming |
| --- | --- | --- |
| `/usr/local/bin/before-notebook.d/` | startup hooks, run in name order by docker-stacks | `NN-<component>`: two-digit order, then the component name |
| `/usr/local/bin/` | command links into the component's prefix | the command's own name |
| `/etc/profile.d/` | login shell setup | `<component>.sh` or the upstream name |
| `/etc/bash.bashrc.d/` | interactive shell setup (all bash terminals) | `<component>.sh` |
| `/usr/local/etc/jupyter/` | Jupyter config from components outside the Jupyter environment | `jupyter_server_config.py` is Selkies'; others use `jupyter_server_config.d/<component>.json` |
| `/opt/scidesktop/` | scidesktop's own scripts; `manifest.d/<component>.json` | `<component>.json` |
| `/etc/scidesktop/home-defaults/` | files copied into each user's home at start, never overwriting the user's own (derived images' default settings) | the path the file should have in the home |

The layer check enforces what it can:

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

### Order and layers

The assembly copies components from least to most frequently changed. Each `COPY
--link` layer depends only on its own component, so updating one component leaves every
other component's layer identical; nodes download only what changed. Keep new components
in that order.

## Adding a component

1. `components/<component>/Dockerfile` with `rootfs`, `component` and `test` stages (copy
   an existing component, e.g. `components/lmod`), and `rootfs/` for its integration files.
2. Versions in `docker-bake.hcl` with `# renovate:` comments; targets `<component>`
   and `<component>-test`; add `<component>-test` to group `test`.
3. If it goes into the image: add it to the `scidesktop` target's contexts and
   one `COPY --link --from=<component> / /` line to `images/scidesktop/Dockerfile`.
4. A Renovate group for `components/<component>/**` and its dependency names.
5. `python3 test/contract.py static`, build, `python3 test/contract.py layers`,
   `./test/smoke.sh`.
