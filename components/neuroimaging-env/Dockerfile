# syntax=docker/dockerfile:1
# Neuroimaging Python analysis kernel and CLIs at /opt/neuroimaging-env:
# nibabel, nipype, niwrap, pydra, nipoppy, ipyniivue (with shared frontend
# bundle & WebGL cleanup patch), datalad (+ datalad-osf, osfclient),
# matplotlib, scipy, pandas, xnat, watermark, nf-core. Installed in its own
# prefix, registered as a Jupyter kernel under /usr/local/share/jupyter/kernels,
# with domain CLIs symlinked into /usr/local/bin so jupyter-env stays lean for
# non-neuroimaging desktops.

ARG UBUNTU_IMAGE
FROM ${UBUNTU_IMAGE} AS build
ARG TARGETARCH
ARG APT_CACHE_ID
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=private \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=private \
    apt-get update && apt-get install --no-install-recommends -y ca-certificates gcc libc6-dev
RUN --mount=type=bind,from=components,source=check-lock,target=/usr/local/bin/check-lock \
    --mount=type=bind,source=.,target=/src \
    check-lock /src/environment.yml /src/linux-*.lock \
    && check-lock /src/requirements.in /src/requirements.lock
COPY --from=micromamba /usr/local/bin/micromamba /usr/local/bin/micromamba
COPY linux-*.lock requirements.lock patch_ipyniivue.py /tmp/
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    --mount=type=bind,from=components,source=trim-python-env,target=/usr/local/bin/trim-python-env \
    micromamba create --yes --root-prefix /tmp/mamba-root --prefix /opt/neuroimaging-env \
        --file "/tmp/$(target-arch conda).lock" \
    && /opt/neuroimaging-env/bin/python -m pip install --no-cache-dir --no-deps --require-hashes \
        --no-compile -r /tmp/requirements.lock \
    && ipyniivue_dir="$(/opt/neuroimaging-env/bin/python -c 'import ipyniivue, pathlib; print(pathlib.Path(ipyniivue.__file__).parent)')" \
    && /opt/neuroimaging-env/bin/python /tmp/patch_ipyniivue.py "${ipyniivue_dir}" /opt/neuroimaging-env/static \
    && /opt/neuroimaging-env/bin/python -m ipykernel install --prefix /opt/neuroimaging-env \
        --name neuroimaging \
        --display-name "Neuroimaging (Python $(/opt/neuroimaging-env/bin/python -c 'import sys; print("%d.%d" % sys.version_info[:2])'))" \
        --env PATH '/opt/neuroimaging-env/bin:${PATH}' \
        --env PYTHONNOUSERSITE 1 \
    && install -d -m 0755 /out/usr/local/share/jupyter/kernels /out/usr/local/bin /out/opt/scidesktop/manifest.d \
    && mv /opt/neuroimaging-env/share/jupyter/kernels/neuroimaging /out/usr/local/share/jupyter/kernels/neuroimaging \
    && rm -rf /opt/neuroimaging-env/share/jupyter/kernels/python3 \
    && for cmd in nf-core nipoppy nipoppy-gui bosh nipypecli; do \
         test -x "/opt/neuroimaging-env/bin/${cmd}" || exit 1; \
         ln -s "/opt/neuroimaging-env/bin/${cmd}" "/out/usr/local/bin/${cmd}" || exit 1; \
       done \
    && /opt/neuroimaging-env/bin/python -c 'import importlib.metadata as m, json; pkgs = ("nibabel", "nipype", "niwrap", "pydra", "nipoppy", "ipyniivue", "datalad", "nf-core"); json.dump({p: m.version(p) for p in pkgs}, open("/out/opt/scidesktop/manifest.d/neuroimaging-env.json", "w"))' \
    && cat /out/opt/scidesktop/manifest.d/neuroimaging-env.json \
    && trim-python-env /opt/neuroimaging-env \
    && rm -rf /tmp/mamba-root /opt/neuroimaging-env/conda-meta/history \
    && chmod -R a+rX,go-w /opt/neuroimaging-env /out

FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /opt/neuroimaging-env /opt/neuroimaging-env
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,from=jupyter-env,source=/usr/local/etc/jupyter,target=/usr/local/etc/jupyter \
    /opt/neuroimaging-env/bin/python -c 'import json, os, pathlib, nibabel, nipype, niwrap, pydra, nipoppy, ipyniivue, datalad, matplotlib, scipy, pandas, osfclient, watermark, xnat; spec = json.load(open("/usr/local/share/jupyter/kernels/neuroimaging/kernel.json")); assert os.access(spec["argv"][0], os.X_OK), spec["argv"]; assert spec["env"].get("PYTHONNOUSERSITE") == "1", spec["env"]; wjs = (pathlib.Path(ipyniivue.__file__).parent / "static/widget.js").read_text(); assert "scidesktop-ipyniivue-shared-bundle" in wjs; assets = list(pathlib.Path("/opt/neuroimaging-env/static").glob("scidesktop-ipyniivue.*.js")); assert len(assets) == 1 and "scidesktop-ipyniivue-model-cleanup" in assets[0].read_text(); print("neuroimaging-env ok:", spec["display_name"])' \
    && /opt/neuroimaging-env/bin/python -m pip check \
    && nf-core --version >/dev/null \
    && nipoppy --version >/dev/null \
    && bosh version >/dev/null \
    && nipypecli --help >/dev/null \
    && cfg="$(PATH="/opt/conda/bin:${PATH}" jupyter server --show-config 2>&1)" \
    && printf '%s\n' "${cfg}" | grep -q "neuroimaging_env_assets.*True" \
    && /opt/conda/bin/python -c 'import sys; sys.path.append("/opt/neuroimaging-env/server_ext"); import neuroimaging_env_assets; assert hasattr(neuroimaging_env_assets, "_load_jupyter_server_extension")' \
    && test -r /opt/scidesktop/manifest.d/neuroimaging-env.json
