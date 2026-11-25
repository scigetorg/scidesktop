# syntax=docker/dockerfile:1
# Preclinical imaging Python analysis kernel at /opt/preclinical-env:
# numpy, scipy, pandas, scikit-image, scikit-learn, statsmodels, matplotlib,
# seaborn, dask, xarray, imageio, tifffile, zarr, pydicom, SimpleITK, nibabel,
# nilearn, ipyniivue, brkraw (Bruker ParaVision MRI I/O), and watermark.
# Installed in its own prefix and registered as a Jupyter kernel under
# /usr/local/share/jupyter/kernels so jupyter-env stays lean for
# non-preclinical desktops.

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
    micromamba create --yes --root-prefix /tmp/mamba-root --prefix /opt/preclinical-env \
        --file "/tmp/$(target-arch conda).lock" \
    && /opt/preclinical-env/bin/python -m pip install --no-cache-dir --no-deps --require-hashes \
        --only-binary :all: --no-compile -r /tmp/requirements.lock \
    && /opt/preclinical-env/bin/python -m ipykernel install --prefix /opt/preclinical-env \
        --name preclinical \
        --display-name "Preclinical (Python $(/opt/preclinical-env/bin/python -c 'import sys; print("%d.%d" % sys.version_info[:2])'))" \
        --env PATH '/opt/preclinical-env/bin:${PATH}' \
        --env PYTHONNOUSERSITE 1 \
    && install -d -m 0755 /out/usr/local/share/jupyter/kernels /out/opt/scidesktop/manifest.d \
    && mv /opt/preclinical-env/share/jupyter/kernels/preclinical /out/usr/local/share/jupyter/kernels/preclinical \
    && rm -rf /opt/preclinical-env/share/jupyter/kernels/python3 \
    && /opt/preclinical-env/bin/python -c 'import importlib.metadata as m, json; pkgs = ("numpy", "scipy", "scikit-image", "scikit-learn", "statsmodels", "tifffile", "zarr", "pydicom", "SimpleITK", "nibabel", "nilearn", "ipyniivue", "brkraw", "dask", "xarray"); json.dump({p: m.version(p) for p in pkgs}, open("/out/opt/scidesktop/manifest.d/preclinical-env.json", "w"))' \
    && cat /out/opt/scidesktop/manifest.d/preclinical-env.json \
    && trim-python-env /opt/preclinical-env \
    && rm -rf /tmp/mamba-root /opt/preclinical-env/conda-meta/history \
    && chmod -R a+rX,go-w /opt/preclinical-env /out

FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /opt/preclinical-env /opt/preclinical-env
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN /opt/preclinical-env/bin/python -c 'import json, os, numpy, scipy, pandas, matplotlib, skimage, sklearn, statsmodels, seaborn, dask, xarray, imageio, tifffile, zarr, pydicom, SimpleITK, nibabel, nilearn, ipyniivue, brkraw, watermark; spec = json.load(open("/usr/local/share/jupyter/kernels/preclinical/kernel.json")); assert os.access(spec["argv"][0], os.X_OK), spec["argv"]; assert spec["env"].get("PYTHONNOUSERSITE") == "1", spec["env"]; print("preclinical-env ok:", spec["display_name"], "SimpleITK:", SimpleITK.Version_VersionString())' \
    && /opt/preclinical-env/bin/python -m pip check \
    && test -r /opt/scidesktop/manifest.d/preclinical-env.json
