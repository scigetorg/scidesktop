# syntax=docker/dockerfile:1
# Data Science Python analysis kernel at /opt/datascience-env:
# numpy, scipy, pandas, polars, pyarrow, duckdb (+ duckdb-engine, jupysql),
# scikit-learn, statsmodels, xgboost, lightgbm, optuna, shap, matplotlib,
# seaborn, plotly, altair, sqlalchemy, and watermark. Installed in its own
# prefix and registered as a Jupyter kernel under /usr/local/share/jupyter/kernels
# so jupyter-env stays lean for non-data-science desktops.

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
    micromamba create --yes --root-prefix /tmp/mamba-root --prefix /opt/datascience-env \
        --file "/tmp/$(target-arch conda).lock" \
    && /opt/datascience-env/bin/python -m pip install --no-cache-dir --no-deps --require-hashes \
        --only-binary :all: --no-compile -r /tmp/requirements.lock \
    && /opt/datascience-env/bin/python -m ipykernel install --prefix /opt/datascience-env \
        --name datascience \
        --display-name "Data Science (Python $(/opt/datascience-env/bin/python -c 'import sys; print("%d.%d" % sys.version_info[:2])'))" \
        --env PATH '/opt/datascience-env/bin:${PATH}' \
        --env PYTHONNOUSERSITE 1 \
    && install -d -m 0755 /out/usr/local/share/jupyter/kernels /out/opt/scidesktop/manifest.d \
    && mv /opt/datascience-env/share/jupyter/kernels/datascience /out/usr/local/share/jupyter/kernels/datascience \
    && rm -rf /opt/datascience-env/share/jupyter/kernels/python3 \
    && /opt/datascience-env/bin/python -c 'import importlib.metadata as m, json; pkgs = ("numpy", "scipy", "pandas", "polars", "pyarrow", "duckdb", "scikit-learn", "statsmodels", "xgboost", "lightgbm", "optuna", "shap", "plotly", "altair", "jupysql"); json.dump({p: m.version(p) for p in pkgs}, open("/out/opt/scidesktop/manifest.d/datascience-env.json", "w"))' \
    && cat /out/opt/scidesktop/manifest.d/datascience-env.json \
    && trim-python-env /opt/datascience-env \
    && rm -rf /tmp/mamba-root /opt/datascience-env/conda-meta/history \
    && chmod -R a+rX,go-w /opt/datascience-env /out

FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /opt/datascience-env /opt/datascience-env
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN /opt/datascience-env/bin/python -c 'import json, os, numpy, scipy, pandas, polars, pyarrow, duckdb, duckdb_engine, sklearn, statsmodels, xgboost, lightgbm, optuna, shap, matplotlib, seaborn, plotly, altair, sqlalchemy, sql, watermark; spec = json.load(open("/usr/local/share/jupyter/kernels/datascience/kernel.json")); assert os.access(spec["argv"][0], os.X_OK), spec["argv"]; assert spec["env"].get("PYTHONNOUSERSITE") == "1", spec["env"]; print("datascience-env ok:", spec["display_name"])' \
    && /opt/datascience-env/bin/python -m pip check \
    && test -r /opt/scidesktop/manifest.d/datascience-env.json
