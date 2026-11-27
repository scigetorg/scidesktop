# syntax=docker/dockerfile:1
# datadesktop: scidesktop for general data science.
#
# `docker buildx bake datadesktop` builds scidesktop and the components below
# from this repository and passes them in under these names; nothing is
# pulled from a registry. A plain `docker build` of this folder fails, because
# no image of those names exists outside bake.
#
#   sciget-datascience narrows sciget to the datascience catalog only
#   datascience-env    isolated Python 3.13 Data Science kernel (numpy, scipy,
#                      pandas, polars, pyarrow, duckdb, jupysql, scikit-learn,
#                      statsmodels, xgboost, lightgbm, optuna, shap, matplotlib,
#                      seaborn, plotly, altair, sqlalchemy)
#   ai-ready           Intersect Australia's AI Ready workshop: its notebooks
#                      and kernel, plus Airflow, MLflow and PostgreSQL in every
#                      session; JupyterLab stays the landing page and its
#                      launcher opens Airflow and MLflow (docs/ai-ready.md)
#
# Slurm (+ jupyterlab-slurm), VS Code (+ core extensions), DataLad,
# workflow engines (Nextflow, nf-test, Snakemake), VirtualGL, scigethelpers,
# coding agents, ACP adapters, T3 Code and T3 Connect are inherited from
# scidesktop.

FROM scidesktop-base

COPY --link --from=sciget-datascience / /
COPY --link --from=datascience-env / /
COPY --link --from=ai-ready / /

ENV SCIDESKTOP_FLAVOUR=datadesktop

LABEL org.opencontainers.image.title="datadesktop" \
      org.opencontainers.image.description="scidesktop for data science: datascience sciget catalog and locked Python 3.13 tabular, SQL, statistical and ML kernel, and the AI Ready workshop"
