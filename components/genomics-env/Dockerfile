# syntax=docker/dockerfile:1
# Genomics and single-cell Python analysis kernel at /opt/genomics-env:
# numpy, scipy, pandas, polars, pyarrow, h5py, zarr, dask, xarray, numba,
# scikit-learn, statsmodels, matplotlib, seaborn, plotly, biopython, anndata,
# scanpy, mudata (for OpenPipelines .h5mu/.h5ad workflows), python-igraph,
# leidenalg, umap-learn, pyyaml, jsonschema, nf-core, and watermark.
# Installed in its own prefix and registered as a Jupyter kernel under
# /usr/local/share/jupyter/kernels so jupyter-env stays lean for non-genomics
# desktops.

ARG UBUNTU_IMAGE
FROM ${UBUNTU_IMAGE} AS build
ARG TARGETARCH
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get install --no-install-recommends -y ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN --mount=type=bind,from=components,source=check-lock,target=/usr/local/bin/check-lock \
    --mount=type=bind,source=.,target=/src \
    check-lock /src/environment.yml /src/linux-*.lock \
    && check-lock /src/requirements.in /src/requirements.lock
COPY --from=micromamba /usr/local/bin/micromamba /usr/local/bin/micromamba
COPY linux-*.lock requirements.lock /tmp/
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    --mount=type=bind,from=components,source=trim-python-env,target=/usr/local/bin/trim-python-env \
    micromamba create --yes --root-prefix /tmp/mamba-root --prefix /opt/genomics-env \
        --file "/tmp/$(target-arch conda).lock" \
    && /opt/genomics-env/bin/python -m pip install --no-cache-dir --no-deps --require-hashes \
        --only-binary :all: --no-compile -r /tmp/requirements.lock \
    && /opt/genomics-env/bin/python -m ipykernel install --prefix /opt/genomics-env \
        --name genomics \
        --display-name "Genomics (Python $(/opt/genomics-env/bin/python -c 'import sys; print("%d.%d" % sys.version_info[:2])'))" \
        --env PATH '/opt/genomics-env/bin:${PATH}' \
        --env PYTHONNOUSERSITE 1 \
    && install -d -m 0755 /out/usr/local/share/jupyter/kernels /out/opt/scidesktop/manifest.d \
    && mv /opt/genomics-env/share/jupyter/kernels/genomics /out/usr/local/share/jupyter/kernels/genomics \
    && rm -rf /opt/genomics-env/share/jupyter/kernels/python3 \
    && /opt/genomics-env/bin/python -c 'import importlib.metadata as m, json; pkgs = ("numpy", "scipy", "pandas", "polars", "pyarrow", "h5py", "zarr", "dask", "xarray", "scikit-learn", "statsmodels", "biopython", "anndata", "scanpy", "mudata", "igraph", "leidenalg", "umap-learn", "PyYAML", "jsonschema", "nf-core"); json.dump({p: m.version(p) for p in pkgs}, open("/out/opt/scidesktop/manifest.d/genomics-env.json", "w"))' \
    && cat /out/opt/scidesktop/manifest.d/genomics-env.json \
    && trim-python-env /opt/genomics-env \
    && rm -rf /tmp/mamba-root /opt/genomics-env/conda-meta/history \
    && chmod -R a+rX,go-w /opt/genomics-env /out

FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /opt/genomics-env /opt/genomics-env
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN /opt/genomics-env/bin/python -c 'import json, os, numpy, scipy, pandas, polars, pyarrow, h5py, zarr, dask, xarray, numba, sklearn, statsmodels, matplotlib, seaborn, plotly, Bio, anndata, scanpy, mudata, igraph, leidenalg, umap, yaml, jsonschema, nf_core, watermark; spec = json.load(open("/usr/local/share/jupyter/kernels/genomics/kernel.json")); assert os.access(spec["argv"][0], os.X_OK), spec["argv"]; assert spec["env"].get("PYTHONNOUSERSITE") == "1", spec["env"]; print("genomics-env ok:", spec["display_name"], "scanpy:", scanpy.__version__, "mudata:", mudata.__version__, "biopython:", Bio.__version__)' \
    && /opt/genomics-env/bin/python -m pip check \
    && test -r /opt/scidesktop/manifest.d/genomics-env.json
