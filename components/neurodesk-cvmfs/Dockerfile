# syntax=docker/dockerfile:1
# The Neurodesk CVMFS repository for the base's CVMFS client: its mirrors,
# the public key its content is signed with, and the repository as the
# default one to mount in internal mode. Configuration only; the client is
# the OS layer's and the module folders are found by sciget's
# /etc/scidesktop/modulepath.d/60-neurodesk-cvmfs. Not part of the base
# image; domain images copy it (docs/images.md).

ARG UBUNTU_IMAGE

# Integration files from rootfs/ at their image paths, readable and without
# group or other write permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
ARG TARGETARCH
ARG APT_CACHE_ID
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y openssl
COPY rootfs/ /rootfs/
# The manifest records the key by its fingerprint, so a changed key shows in
# an image's manifest; a file that is not a public key fails here.
RUN chmod -R a+rX,go-w /rootfs \
    && key=/rootfs/etc/cvmfs/keys/ardc.edu.au/neurodesk.ardc.edu.au.pub \
    && fingerprint="$(openssl pkey -pubin -in "${key}" -outform DER | sha256sum | cut -d ' ' -f 1)" \
    && [ "${#fingerprint}" -eq 64 ] \
    && install -d -m 0755 /rootfs/opt/scidesktop/manifest.d \
    && printf '{"repository": "neurodesk.ardc.edu.au", "public_key_sha256": "%s"}\n' "${fingerprint}" \
        > /rootfs/opt/scidesktop/manifest.d/neurodesk-cvmfs.json

FROM scratch AS component
COPY --from=rootfs /rootfs/ /

FROM os AS test
COPY --from=component / /
RUN --mount=type=bind,source=test.sh,target=/tmp/test.sh bash /tmp/test.sh
