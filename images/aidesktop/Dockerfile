# syntax=docker/dockerfile:1
# aidesktop: scidesktop with the AI Ready workshop (a workshop notebook
# kernel, Airflow, MLflow and PostgreSQL in every session).
#
# `docker buildx bake aidesktop` builds scidesktop and the components below
# from this repository and passes them in under these names; nothing is
# pulled from a registry. A plain `docker build` of this folder fails, because
# no image of those names exists outside bake.
#
# The workshop itself is the ai-ready component (components/ai-ready). The coding agents and T3 Code are the coding-agents and
# t3-code components, shared with microdesktop. Changes to them belong there,
# not here. Copying a component is all an image does for it; see
# docs/images.md.

FROM scidesktop-base

COPY --link --from=sciget-neuroimaging / /
COPY --link --from=ai-ready / /
COPY --link --from=coding-agents / /
COPY --link --from=acp-adapters / /
COPY --link --from=t3-code / /
COPY --link --from=t3-connect / /

LABEL org.opencontainers.image.title="aidesktop" \
      org.opencontainers.image.description="scidesktop with the AI Ready workshop"
