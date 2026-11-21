# Images: the base and domain images

This repository builds a family of images, as
[docker-stacks](https://github.com/jupyter/docker-stacks) does. `images/scidesktop`
is the base: the components assembled on the OS layer (see
[components.md](components.md)). Every other folder in `images/` is a domain image
that builds on it and adds what its community needs.

```
images/
  scidesktop/      the base; its Dockerfile only assembles components
  microdesktop/    FROM scidesktop, plus coding-agents and t3-code: microscopy
  aidesktop/       FROM scidesktop, plus ai-ready, coding-agents and t3-code
  neurodesktop/    FROM scidesktop, plus neurodesk-cvmfs, datalad, code-server,
                   coding-agents, t3-code and neurodesk-agents: neuroimaging
```

| Component | scidesktop | microdesktop | aidesktop | neurodesktop |
| --- | --- | --- | --- | --- |
| the base's components | yes | yes | yes | yes |
| `coding-agents`, `t3-code` ([coding-agents.md](coding-agents.md)) | no | yes | yes | yes |
| `ai-ready` ([ai-ready.md](ai-ready.md)) | no | no | yes | no |
| `code-server`, `datalad` ([neurodesktop.md](neurodesktop.md)) | no | no | no | yes |
| `neurodesk-cvmfs`, `neurodesk-agents` ([neurodesktop.md](neurodesktop.md)) | no | no | no | yes |

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
workshop adds 2.6 GB and background services, and the coding agents add
1.3 GB of other vendors' binaries. Such a component lives in `components/`
like any other, with its own test, and stays out of the base's assembly. The
domain images that want it copy it the way the assembly does:

```dockerfile
FROM scidesktop-base

COPY --link --from=ai-ready / /
COPY --link --from=coding-agents / /
COPY --link --from=t3-code / /
```

```hcl
contexts = {
  scidesktop-base = "target:scidesktop"
  ai-ready        = "target:ai-ready"
  coding-agents   = "target:coding-agents"
  t3-code         = "target:t3-code"
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

Several images can copy the same component, as `microdesktop` and `aidesktop`
do, and nodes download its layer once. An image gets the components of the
image it is `FROM` and must not copy them again. Rule S6 checks the `COPY` line,
the bake context, and that nothing is copied twice. The layer rules (L1 to L5)
cover every component an image copies, so an optional component may not
overwrite a file of the base's components either. Rule I1 checks the built
image: it holds its components and no file of any other, which is what keeps
optional components out of `scidesktop`.

An optional component keeps to its own prefix (`/opt/<component>`) and the
[shared places](components.md#shared-places).

## What a domain image may do

Anything a Dockerfile can, inside its own folder: install packages, add
sciget catalogs and settings for every user (`sciget catalog add --system`,
`sciget config set --system`), configuration, branding and hooks. The base is built as the notebook
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

`PUBLISH` lists `scidesktop`, `aidesktop` and `neurodesktop`. A published
domain image gets its own package, `ghcr.io/<owner>/<name>`.

## Forks

A community that wants its own image without contributing it here forks the
repository and adds a folder to `images/`. Base improvements made in the fork
come back as pull requests against `components/`.
