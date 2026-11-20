# syntax=docker/dockerfile:1
# aimicrodesktop: microdesktop with the AI Ready workshop (a workshop notebook
# kernel, Airflow, MLflow and PostgreSQL in every session).
#
# `docker buildx bake aimicrodesktop` builds microdesktop and the ai-ready component
# from this repository and passes them in under the names below; nothing is
# pulled from a registry. A plain `docker build` of this folder fails, because
# no image of those names exists outside bake.
#
# The workshop itself is the ai-ready component (components/ai-ready), shared
# with aidesktop. Changes to it belong there, not here; see
# docs/images.md.

FROM microdesktop-base

COPY --link --from=ai-ready / /

LABEL org.opencontainers.image.title="aimicrodesktop" \
      org.opencontainers.image.description="microdesktop with the AI Ready workshop"

# Owner: ai-ready. Jupyter reads the component's server configuration and
# finds its kernel through these folders.
ENV JUPYTER_CONFIG_PATH=/opt/ai-ready/etc/jupyter \
    JUPYTER_PATH=/opt/ai-ready/share/jupyter
