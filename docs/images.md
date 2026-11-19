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
3. In `.github/workflows/image.yml`: add it to the cache loop, set its tag to
   `<name>:ci` and add a smoke test step.
4. `python3 test/contract.py static`, `docker buildx bake <name>`,
   `./test/smoke.sh <name>`.

## Forks

A community that wants its own image without contributing it here forks the
repository and adds a folder to `images/`. Base improvements made in the fork
come back as pull requests against `components/`.
