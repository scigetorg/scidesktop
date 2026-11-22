# syntax=docker/dockerfile:1
# Neuroimaging Python analysis kernel at /opt/neuroimaging-env: nibabel,
# nipype, niwrap, pydra, nipoppy, ipyniivue, datalad (+ datalad-osf, osfclient),
# matplotlib, scipy, pandas, xnat, watermark, nf-core. Installed in its own
# prefix and registered as a Jupyter kernel under /usr/local/share/jupyter/kernels
# so jupyter-env stays lean for non-neuroimaging desktops.

ARG UBUNTU_IMAGE
FROM ${UBUNTU_IMAGE} AS build
ARG TARGETARCH
ARG APT_CACHE_ID
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y ca-certificates gcc libc6-dev
RUN --mount=type=bind,from=components,source=check-lock,target=/usr/local/bin/check-lock \
    --mount=type=bind,source=.,target=/src \
    check-lock /src/environment.yml /src/linux-*.lock \
    && check-lock /src/requirements.in /src/requirements.lock
COPY --from=micromamba /usr/local/bin/micromamba /usr/local/bin/micromamba
COPY linux-*.lock requirements.lock /tmp/
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    micromamba create --yes --root-prefix /tmp/mamba-root --prefix /opt/neuroimaging-env \
        --file "/tmp/$(target-arch conda).lock" \
    && /opt/neuroimaging-env/bin/python -m pip install --no-cache-dir --no-deps --require-hashes \
        --no-compile -r /tmp/requirements.lock \
    && /opt/neuroimaging-env/bin/python -m compileall -q /opt/neuroimaging-env/lib \
    && /opt/neuroimaging-env/bin/python -m ipykernel install --prefix /opt/neuroimaging-env \
        --name neuroimaging \
        --display-name "Neuroimaging (Python $(/opt/neuroimaging-env/bin/python -c 'import sys; print("%d.%d" % sys.version_info[:2])'))" \
        --env PATH '/opt/neuroimaging-env/bin:${PATH}' \
    && install -d -m 0755 /out/usr/local/share/jupyter/kernels /out/opt/scidesktop/manifest.d \
    && mv /opt/neuroimaging-env/share/jupyter/kernels/neuroimaging /out/usr/local/share/jupyter/kernels/neuroimaging \
    && rm -rf /opt/neuroimaging-env/share/jupyter/kernels/python3 \
    && /opt/neuroimaging-env/bin/python -c 'import importlib.metadata as m, json; pkgs = ("nibabel", "nipype", "niwrap", "pydra", "nipoppy", "ipyniivue", "datalad", "nf-core"); json.dump({p: m.version(p) for p in pkgs}, open("/out/opt/scidesktop/manifest.d/neuroimaging-env.json", "w"))' \
    && cat /out/opt/scidesktop/manifest.d/neuroimaging-env.json \
    && rm -rf /tmp/mamba-root /opt/neuroimaging-env/conda-meta/history \
    && chmod -R a+rX,go-w /opt/neuroimaging-env /out

FROM scratch AS component
COPY --from=build /opt/neuroimaging-env /opt/neuroimaging-env
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN /opt/neuroimaging-env/bin/python -c 'import json, os, nibabel, nipype, niwrap, pydra, nipoppy, ipyniivue, datalad, matplotlib, scipy, pandas, osfclient, watermark, xnat; spec = json.load(open("/usr/local/share/jupyter/kernels/neuroimaging/kernel.json")); assert os.access(spec["argv"][0], os.X_OK), spec["argv"]; print("neuroimaging-env ok:", spec["display_name"])' \
    && /opt/neuroimaging-env/bin/python -m pip check \
    && test -r /opt/scidesktop/manifest.d/neuroimaging-env.json
