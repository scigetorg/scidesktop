# Images: the base and domain images

This repository builds a family of images, as
[docker-stacks](https://github.com/jupyter/docker-stacks) does. `images/scidesktop`
is the base: the components assembled on the OS layer (see
[components.md](components.md)). Every other folder in `images/` is a domain image
that builds on it and adds what its community needs.

```
images/
  scidesktop/      the base; its Dockerfile only assembles components
  microdesktop/    FROM scidesktop: microscopy
```

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
  contexts = { scidesktop-base = "target:scidesktop" }
  tags     = [MICRODESKTOP_IMAGE]
  output   = ["type=docker"]
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

## Adding an image

1. Copy `images/microdesktop` to `images/<name>` and change the names in its
   `Dockerfile` and `README.md`.
2. In `docker-bake.hcl`: a variable `<NAME>_IMAGE` for its tag (list it in
   `NOT_RENOVATED` in `test/contract.py`), a target like `microdesktop`'s, and
   the target in group `default`.
3. `python3 test/contract.py static`, `docker buildx bake <name>`,
   `./test/smoke.sh <name>`.
4. To publish it, add its name to `PUBLISH` in `.github/workflows/image.yml`.

## CI and publishing

`.github/workflows/image.yml` finds the images by their folders, so a new
image is built, cached and smoke-tested on amd64 and arm64 without a change
to the workflow.

- **Pull requests:** one job per architecture, each on a runner of that
  architecture (no emulation). It runs the contract checks, builds every
  component, test and image, and smoke-tests every image. Nothing is pushed.
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

`PUBLISH` lists `scidesktop` only. A published domain image gets its own
package, `ghcr.io/<owner>/<name>`.

## Forks

A community that wants its own image without contributing it here forks the
repository and adds a folder to `images/`. Base improvements made in the fork
come back as pull requests against `components/`.
