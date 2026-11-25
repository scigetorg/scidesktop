# syntax=docker/dockerfile:1
# Molecular imaging Python analysis kernel at /opt/molecular-imaging-env:
# numpy, scipy, pandas, scikit-image, scikit-learn, statsmodels, matplotlib,
# seaborn, pydicom, SimpleITK, nibabel, nilearn, highdicom (DICOM PET/SEG/SR),
# ipyniivue, and watermark.
# Installed in its own prefix and registered as a Jupyter kernel under
# /usr/local/share/jupyter/kernels so jupyter-env stays lean for
# non-molecular-imaging desktops.

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
    micromamba create --yes --root-prefix /tmp/mamba-root --prefix /opt/molecular-imaging-env \
        --file "/tmp/$(target-arch conda).lock" \
    && /opt/molecular-imaging-env/bin/python -m pip install --no-cache-dir --no-deps --require-hashes \
        --only-binary :all: --no-compile -r /tmp/requirements.lock \
    && /opt/molecular-imaging-env/bin/python -m ipykernel install --prefix /opt/molecular-imaging-env \
        --name molecular-imaging \
        --display-name "Molecular Imaging (Python $(/opt/molecular-imaging-env/bin/python -c 'import sys; print("%d.%d" % sys.version_info[:2])'))" \
        --env PATH '/opt/molecular-imaging-env/bin:${PATH}' \
        --env PYTHONNOUSERSITE 1 \
    && install -d -m 0755 /out/usr/local/share/jupyter/kernels /out/opt/scidesktop/manifest.d \
    && mv /opt/molecular-imaging-env/share/jupyter/kernels/molecular-imaging /out/usr/local/share/jupyter/kernels/molecular-imaging \
    && rm -rf /opt/molecular-imaging-env/share/jupyter/kernels/python3 \
    && /opt/molecular-imaging-env/bin/python -c 'import importlib.metadata as m, json; pkgs = ("numpy", "scipy", "scikit-image", "scikit-learn", "statsmodels", "pydicom", "highdicom", "SimpleITK", "nibabel", "nilearn", "ipyniivue"); json.dump({p: m.version(p) for p in pkgs}, open("/out/opt/scidesktop/manifest.d/molecular-imaging-env.json", "w"))' \
    && cat /out/opt/scidesktop/manifest.d/molecular-imaging-env.json \
    && trim-python-env /opt/molecular-imaging-env \
    && rm -rf /tmp/mamba-root /opt/molecular-imaging-env/conda-meta/history \
    && chmod -R a+rX,go-w /opt/molecular-imaging-env /out

FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /opt/molecular-imaging-env /opt/molecular-imaging-env
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN /opt/molecular-imaging-env/bin/python -c 'import json, os, numpy, scipy, pandas, matplotlib, skimage, sklearn, statsmodels, seaborn, pydicom, highdicom, SimpleITK, nibabel, nilearn, ipyniivue, watermark; spec = json.load(open("/usr/local/share/jupyter/kernels/molecular-imaging/kernel.json")); assert os.access(spec["argv"][0], os.X_OK), spec["argv"]; assert spec["env"].get("PYTHONNOUSERSITE") == "1", spec["env"]; print("molecular-imaging-env ok:", spec["display_name"], "SimpleITK:", SimpleITK.Version_VersionString())' \
    && /opt/molecular-imaging-env/bin/python -m pip check \
    && test -r /opt/scidesktop/manifest.d/molecular-imaging-env.json
