# Images: the base and domain images

This repository builds a family of images, as
[docker-stacks](https://github.com/jupyter/docker-stacks) does. `images/scidesktop`
is the base: the components assembled on the OS layer (see
[components.md](components.md)). Every other folder in `images/` is a domain image
that builds on it and adds what its community needs.

```
images/
  scidesktop/      the base; includes all sciget domains (sciget-all),
                   Slurm + jupyterlab-slurm, VS Code (code-server, vscode-core),
                   DataLad, workflow engines (Nextflow, nf-test, Snakemake),
                   VirtualGL, scigethelpers-cli, coding agents, ACP adapters,
                   T3 Code and T3 Connect
  microdesktop/    FROM scidesktop, plus sciget-microscopy,
                   jupyterlab-neuroglancer and microscopy-env: microscopy
  datadesktop/     FROM scidesktop, plus datascience-env: general data science
  aidesktop/       FROM scidesktop, plus sciget-datascience and ai-ready:
                   datascience
  neurodesktop/    FROM scidesktop, plus sciget-neuroimaging, neurodesk-cvmfs,
                   vscode-niivue, vscode-coding-agents, jupyterlab-niivue,
                   jupyterlab-freebrowse, neurodesk-agents, neuroimaging-env
                   and neurodesk-compat: neuroimaging
```

| Component | scidesktop | microdesktop | datadesktop | aidesktop | neurodesktop |
| --- | --- | --- | --- | --- | --- |
| core base (`startup`, `lmod`, `apptainer`, `selkies`, `jupyter-env`, `sciget`, `slurm`, `jupyterlab-slurm`) | yes | yes | yes | yes | yes |
| `virtualgl`, `datalad`, `workflow-engines`, `scigethelpers-cli` | yes | yes | yes | yes | yes |
| `code-server`, `vscode-core` ([neurodesktop.md](neurodesktop.md#vs-code)) | yes | yes | yes | yes | yes |
| `sciget-all` ([tool catalogs](#tool-catalogs)) | yes | narrowed | yes | narrowed | narrowed |
| `coding-agents`, `t3-code`, `antigravity-acp` ([coding-agents.md](coding-agents.md)), `t3-connect` ([t3-connect.md](t3-connect.md)) | yes | yes | yes | yes | yes |
| `acp-adapters` ([jupyter-ai.md](jupyter-ai.md#the-adapters-for-codex-and-claude-code)) | yes | yes | yes | yes | yes |
| `sciget-neuroimaging` ([tool catalogs](#tool-catalogs)) | no | no | no | no | yes |
| `sciget-microscopy`, `jupyterlab-neuroglancer`, `microscopy-env` ([tool catalogs](#tool-catalogs), [viewers.md](viewers.md)) | no | yes | no | no | no |
| `datascience-env` | no | no | yes | no | no |
| `sciget-datascience`, `ai-ready` ([tool catalogs](#tool-catalogs), [ai-ready.md](ai-ready.md)) | no | no | no | yes | no |
| `jupyterlab-niivue`, `jupyterlab-freebrowse`, `vscode-niivue`, `vscode-coding-agents`, `neuroimaging-env`, `neurodesk-compat` ([viewers.md](viewers.md), [neurodesktop.md](neurodesktop.md)) | no | no | no | no | yes |
| `neurodesk-cvmfs`, `neurodesk-agents` ([neurodesktop.md](neurodesktop.md)) | no | no | no | no | yes |

## How a domain image gets the base

A domain image's Dockerfile starts from the base under a name only bake
defines:

```dockerfile
FROM scidesktop-base
```

and its bake target hands that name the base built in the same run:

```hcl
target "microdesktop" {
  inherits = ["_common"]
  context  = "images/microdesktop"
  contexts = {
    scidesktop-base = "target:scidesktop"
    ...
  }
  tags   = [MICRODESKTOP_IMAGE]
  output = ["type=docker"]
}
```

`docker buildx bake microdesktop` therefore builds scidesktop first (or takes
it from the cache), then microdesktop on top. Nothing is pulled from or pushed
to a registry, and a change to the base rebuilds and retests every image in the
same CI run. A plain `docker build` of the folder fails, because no image called
`scidesktop-base` exists outside bake; that is deliberate, so an image never
builds on a stale base by accident. (`FROM scidesktop` would not fail: bake
loads the base into the local image store as `scidesktop:latest`, and a plain
build would take whatever version is stored there.)

## Optional components

Some software is a component but does not belong in every image: the AI Ready
workshop adds 2.6 GB and background services, and `code-server` with its VS Code
extensions adds over 2 GB. Such a component lives in `components/`
like any other, with its own test, and stays out of the base's assembly. The
domain images that want it copy it the way the assembly does:

```dockerfile
FROM scidesktop-base

COPY --link --from=sciget-datascience / /
COPY --link --from=ai-ready / /
```

```hcl
contexts = {
  scidesktop-base    = "target:scidesktop"
  sciget-datascience = "target:sciget-datascience"
  ai-ready           = "target:ai-ready"
}
```

Those two places are all an image writes for a component. The component
brings the rest: its Jupyter tiles and services
([one mechanism for every component](components.md#jupyter-configuration-s8)),
its kernels, start hooks, home defaults, manifest entry and smoke test.

A component can be configuration only, with no software of its own:
`neurodesk-cvmfs` is two files for the base's CVMFS client, and
`neurodesk-agents` supplies one community's defaults for `coding-agents`
through that component's
[extension points](coding-agents.md#extending-them-in-a-domain-image). A
community's defaults then stay out of the generic component, and the image
still only assembles.

Several images can copy the same component,
and nodes download its layer once. An image gets the components of the
image it is `FROM` and must not copy them again. Rule S6 checks the `COPY` line,
the bake context, and that nothing is copied twice. The layer rules (L1 to L5)
cover every component an image copies, so an optional component may not
overwrite a file of the base's components either (with one explicit exception:
domain `sciget-*` catalog components may override `sciget-all`'s
`/etc/sciget/catalogs.json`). Rule I1 checks the built
image: it holds its components and no file of any other, which is what keeps
optional components out of `scidesktop`.

An optional component keeps to its own prefix (`/opt/<component>`) and the
[shared places](components.md#shared-places).

## Tool catalogs

sciget offers the tools of its catalogs. The catalogs every user of an image
gets are sciget's system layer, one file: `/etc/sciget/catalogs.json`. The base
image copies `sciget-all` so plain `scidesktop` offers every published domain
catalog; a domain image narrows the list by copying its own catalog component
over `/etc/sciget/catalogs.json`:

| Component | Catalogs | Also |
| --- | --- | --- |
| `sciget-all` (in `scidesktop`) | `neuroimaging`, `microscopy`, `datascience` | the module folders of containers on the Neurodesk CVMFS repository |
| `sciget-neuroimaging` | `neuroimaging` | |
| `sciget-microscopy` | `microscopy` | |
| `sciget-datascience` | `datascience` | |

<<<<<<< HEAD
`scidesktop` therefore offers both neuroimaging and microscopy tools out of the
box (`test/sciget-all-smoke.sh`). An image with `sciget-microscopy` overrides
`/etc/sciget/catalogs.json` so only the `microscopy` catalog is configured and
every offered tool comes from it (`test/sciget-microscopy-smoke.sh`); an image
with `sciget-neuroimaging` configures only the `neuroimaging` catalog
(`test/sciget-neuroimaging-smoke.sh`). Copying two domain catalog components
into one image still fails rule L1.
=======
`scidesktop` therefore offers neuroimaging, microscopy and datascience tools out
of the box (`test/sciget-all-smoke.sh`). An image with `sciget-microscopy`
overrides `/etc/sciget/catalogs.json` and offers the microscopy tools and no
neuroimaging tool (`test/sciget-microscopy-smoke.sh`); `sciget-neuroimaging`
offers neuroimaging tools only (`test/sciget-neuroimaging-smoke.sh`); and
`sciget-datascience` offers datascience tools only
(`test/sciget-datascience-smoke.sh`). Copying two domain catalog components into
one image still fails rule L1.
>>>>>>> 2b10686 (feat(aidesktop): wire datascience sciget catalog into aidesktop and sciget-all)

These catalogs are published by the
[sciget catalog service](https://apps-catalog.scigetorg.workers.dev/domains.json).
A new domain there becomes an image here with a component like
`components/sciget-microscopy` (one JSON file) and its two-line smoke test.

## What a domain image may do

Anything a Dockerfile can, inside its own folder: install packages,
configuration, branding and hooks. What can be a component is better as
one: the images here only assemble, and their tool catalog is a component
([Tool catalogs](#tool-catalogs)). The base is built as the notebook
user, so switch to `USER root` for system changes and end with `USER ${NB_UID}`.

What it should not do is work around the base. A change every image would want
(a bug fix, a new extension point, a component) goes into `components/` as its
own change, so all images get it.

The contract test (`python3 test/contract.py static`, rule S6) checks that each
folder in `images/` has a bake target of the same name in the `default` group,
built from that folder, and that the stage a domain image builds starts from
`<image>-base` for another image in `images/`, handed in as a bake target.
A component it copies must be copied whole and be a bake context of the image.

## Adding an image

1. Copy `images/microdesktop` to `images/<name>` and change the names in its
   `Dockerfile` and `README.md`.
2. In `docker-bake.hcl`: a variable `<NAME>_IMAGE` for its tag (list it in
   `NOT_RENOVATED` in `test/contract.py`), a target like `microdesktop`'s, and
   the target in group `default`.
3. `python3 test/contract.py static`, `docker buildx bake <name>`,
   `./test/image-smoke.sh <name>`.
4. If the image has behaviour of its own to check, add an executable
   `images/<name>/smoke.sh` that takes the image as its argument. It is for
   what only this image does: the components' checks already run (see
   [Smoke tests](#smoke-tests)).
5. To publish it, add its name to `PUBLISH` in `.github/workflows/image.yml`.

## Smoke tests

`./test/image-smoke.sh <image> [ref]` runs every end-to-end check of one image:

1. `test/contract.py image`: the image holds its components and nothing of any
   other (rule I1).
2. `test/smoke.sh`: the base's checks, which every image must still pass.
3. `test/<component>-smoke.sh` for each component in the image that has one.
   The list is read from the image's `/opt/scidesktop/manifest.d`, so it is
   what the image contains, not what a file says it should.
4. `images/<image>/smoke.sh`, when the image has checks of its own.

An image therefore lists no smoke tests. Copying `ai-ready` into an image is
what makes `test/ai-ready-smoke.sh` run on it.

## CI and publishing

`.github/workflows/image.yml` finds the images by their folders, so a new
image is built, cached and smoke-tested on amd64 and arm64 without a change
to the workflow.

- **Pull requests:** one job per architecture, each on a runner of that
  architecture (no emulation). It runs the contract checks, builds every
  component, test and image, and runs `test/image-smoke.sh` on every image.
  Nothing is pushed.
  The Actions cache holds 10 GB for the repository and evicts the rest. A
  build that fails because a cached layer was evicted while it ran is run
  once more without the cache; any other failure stands.
- **Pushes to `main`:** the same jobs, then each pushes the images named in
  `PUBLISH` to `ghcr.io/<owner>/<image>` under a candidate tag,
  `run-<run id>-<arch>`. When both architectures have passed, the `publish`
  job joins the candidates into one multi-arch image and tags it
  `<short sha>`, `<YYYY-MM-DD>` (the commit's date) and `latest`. If either
  architecture fails, nothing is tagged. Every image gets its `<short sha>`
  tag before any image's date and `latest` tags move, so a failure part way
  leaves those where they were. A run whose commit is no longer the head of
  `main` (a re-run of an older run, or `main` advancing while the run
  publishes) publishes its `<short sha>` and leaves them too: the head is read
  again before each image's tags move
  (`test/publish-manifests-test.sh`). The candidate tags stay in the registry: the multi-arch
  image points at them.

`PUBLISH` lists `scidesktop`, `microdesktop`, `datadesktop`, `aidesktop` and `neurodesktop`. A published
domain image gets its own package, `ghcr.io/<owner>/<name>`.

## Forks

A community that wants its own image without contributing it here forks the
repository and adds a folder to `images/`. Base improvements made in the fork
come back as pull requests against `components/`.
