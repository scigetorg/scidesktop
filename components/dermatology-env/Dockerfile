# syntax=docker/dockerfile:1
# Dermatology Python analysis kernel at /opt/dermatology-env:
# numpy, scipy, pandas, scikit-image, scikit-learn, statsmodels, matplotlib,
# seaborn, dask, xarray, imageio, tifffile, imagecodecs, zarr, ome-zarr, bioio
# (OME-TIFF, OME-Zarr, tifffile), openslide (dermatopathology WSI), pydicom
# (DICOM-VL dermoscopy and clinical photography), colour-science (CIELAB/ITA
# skin colorimetry), trimesh (3D total-body photography meshes), and watermark.
# Installed in its own prefix and registered as a Jupyter kernel under
# /usr/local/share/jupyter/kernels so jupyter-env stays lean for
# non-dermatology desktops.

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
    micromamba create --yes --root-prefix /tmp/mamba-root --prefix /opt/dermatology-env \
        --file "/tmp/$(target-arch conda).lock" \
    && /opt/dermatology-env/bin/python -m pip install --no-cache-dir --no-deps --require-hashes \
        --only-binary :all: --no-compile -r /tmp/requirements.lock \
    && /opt/dermatology-env/bin/python -m ipykernel install --prefix /opt/dermatology-env \
        --name dermatology \
        --display-name "Dermatology (Python $(/opt/dermatology-env/bin/python -c 'import sys; print("%d.%d" % sys.version_info[:2])'))" \
        --env PATH '/opt/dermatology-env/bin:${PATH}' \
        --env PYTHONNOUSERSITE 1 \
    && install -d -m 0755 /out/usr/local/share/jupyter/kernels /out/opt/scidesktop/manifest.d \
    && mv /opt/dermatology-env/share/jupyter/kernels/dermatology /out/usr/local/share/jupyter/kernels/dermatology \
    && rm -rf /opt/dermatology-env/share/jupyter/kernels/python3 \
    && /opt/dermatology-env/bin/python -c 'import importlib.metadata as m, json; pkgs = ("numpy", "scipy", "scikit-image", "scikit-learn", "statsmodels", "tifffile", "zarr", "ome-zarr", "bioio", "bioio-ome-tiff", "bioio-ome-zarr", "openslide-python", "pydicom", "colour-science", "trimesh", "dask", "xarray"); json.dump({p: m.version(p) for p in pkgs}, open("/out/opt/scidesktop/manifest.d/dermatology-env.json", "w"))' \
    && cat /out/opt/scidesktop/manifest.d/dermatology-env.json \
    && trim-python-env /opt/dermatology-env \
    && rm -rf /tmp/mamba-root /opt/dermatology-env/conda-meta/history \
    && chmod -R a+rX,go-w /opt/dermatology-env /out

FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /opt/dermatology-env /opt/dermatology-env
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN /opt/dermatology-env/bin/python -c 'import json, os, numpy, scipy, pandas, matplotlib, skimage, sklearn, statsmodels, seaborn, dask, xarray, imageio, tifffile, imagecodecs, zarr, openslide, pydicom, colour, trimesh, ome_zarr, bioio, bioio_ome_tiff, bioio_ome_zarr, bioio_tifffile, watermark; spec = json.load(open("/usr/local/share/jupyter/kernels/dermatology/kernel.json")); assert os.access(spec["argv"][0], os.X_OK), spec["argv"]; assert spec["env"].get("PYTHONNOUSERSITE") == "1", spec["env"]; print("dermatology-env ok:", spec["display_name"], "openslide:", openslide.__library_version__)' \
    && /opt/dermatology-env/bin/python -m pip check \
    && test -r /opt/scidesktop/manifest.d/dermatology-env.json
