# syntax=docker/dockerfile:1
# Microscopy Python analysis kernel at /opt/microscopy-env:
# numpy, scipy, pandas, scikit-image, scikit-learn, matplotlib, seaborn, dask,
# xarray, imageio, tifffile, imagecodecs, zarr, ome-zarr, bioio (OME-TIFF,
# OME-Zarr, tifffile), and watermark. Installed in its own prefix and registered
# as a Jupyter kernel under /usr/local/share/jupyter/kernels so jupyter-env
# stays lean for non-microscopy desktops.

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
    micromamba create --yes --root-prefix /tmp/mamba-root --prefix /opt/microscopy-env \
        --file "/tmp/$(target-arch conda).lock" \
    && /opt/microscopy-env/bin/python -m pip install --no-cache-dir --no-deps --require-hashes \
        --only-binary :all: --no-compile -r /tmp/requirements.lock \
    && /opt/microscopy-env/bin/python -m ipykernel install --prefix /opt/microscopy-env \
        --name microscopy \
        --display-name "Microscopy (Python $(/opt/microscopy-env/bin/python -c 'import sys; print("%d.%d" % sys.version_info[:2])'))" \
        --env PATH '/opt/microscopy-env/bin:${PATH}' \
        --env PYTHONNOUSERSITE 1 \
    && install -d -m 0755 /out/usr/local/share/jupyter/kernels /out/opt/scidesktop/manifest.d \
    && mv /opt/microscopy-env/share/jupyter/kernels/microscopy /out/usr/local/share/jupyter/kernels/microscopy \
    && rm -rf /opt/microscopy-env/share/jupyter/kernels/python3 \
    && /opt/microscopy-env/bin/python -c 'import importlib.metadata as m, json; pkgs = ("numpy", "scipy", "scikit-image", "tifffile", "zarr", "ome-zarr", "bioio", "bioio-ome-tiff", "bioio-ome-zarr", "dask", "xarray"); json.dump({p: m.version(p) for p in pkgs}, open("/out/opt/scidesktop/manifest.d/microscopy-env.json", "w"))' \
    && cat /out/opt/scidesktop/manifest.d/microscopy-env.json \
    && trim-python-env /opt/microscopy-env \
    && rm -rf /tmp/mamba-root /opt/microscopy-env/conda-meta/history \
    && chmod -R a+rX,go-w /opt/microscopy-env /out

FROM scratch AS component
COPY --from=build /opt/microscopy-env /opt/microscopy-env
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN /opt/microscopy-env/bin/python -c 'import json, os, numpy, scipy, pandas, matplotlib, skimage, sklearn, seaborn, dask, xarray, imageio, tifffile, imagecodecs, zarr, ome_zarr, bioio, bioio_ome_tiff, bioio_ome_zarr, bioio_tifffile, watermark; spec = json.load(open("/usr/local/share/jupyter/kernels/microscopy/kernel.json")); assert os.access(spec["argv"][0], os.X_OK), spec["argv"]; assert spec["env"].get("PYTHONNOUSERSITE") == "1", spec["env"]; print("microscopy-env ok:", spec["display_name"])' \
    && /opt/microscopy-env/bin/python -m pip check \
    && test -r /opt/scidesktop/manifest.d/microscopy-env.json
