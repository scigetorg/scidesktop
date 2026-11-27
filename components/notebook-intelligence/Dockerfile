# syntax=docker/dockerfile:1
# Notebook Intelligence for JupyterLab (BSD-3-Clause) at /opt/notebook-intelligence:
# AI coding assistant and inline completions inside JupyterLab. Installed outside
# /opt/conda with only the delta packages not already provided by jupyter-env;
# the server extension registers via /etc/scidesktop/jupyter_server_config.d and
# the prebuilt labextension is symlinked under /usr/local/share/jupyter/labextensions.
# Included in scidesktop (docs/images.md).

ARG UBUNTU_IMAGE
FROM ${UBUNTU_IMAGE} AS build
ARG TARGETARCH
ARG APT_CACHE_ID
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,id=apt-cache-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_ID}-plain-${TARGETARCH},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install --no-install-recommends -y ca-certificates
# A pin changed without ./lock fails here rather than installing the old lock.
RUN --mount=type=bind,from=components,source=check-lock,target=/usr/local/bin/check-lock \
    --mount=type=bind,source=.,target=/src \
    check-lock /src/requirements.in /src/requirements.lock
COPY requirements.lock /tmp/
COPY patches/ /tmp/patches/
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    /opt/conda/bin/python -m pip install \
        --no-cache-dir --no-deps --require-hashes --no-compile \
        --target /out/opt/notebook-intelligence/lib -r /tmp/requirements.lock \
    # claude-agent-sdk vendors a ~260 MB Claude Code CLI binary; remove it so
    # Notebook Intelligence uses /usr/local/bin/claude from coding-agents.
    # test -d fails loudly if the SDK relocates its bundle.
    && test -d /out/opt/notebook-intelligence/lib/claude_agent_sdk/_bundled \
    && rm -rf /out/opt/notebook-intelligence/lib/claude_agent_sdk/_bundled \
    # Keep a single copy of the ~24 MB labextension bundle and strip sourcemaps.
    && labext=/out/opt/notebook-intelligence/lib/notebook_intelligence/labextension \
    && test -f "${labext}/package.json" \
    && find "${labext}/static" -type f -name 'remoteEntry*.js' | grep -q . \
    && rm -rf /out/opt/notebook-intelligence/lib/share/jupyter/labextensions/@plmbr/notebook-intelligence \
    && rm -rf /out/opt/notebook-intelligence/lib/bin \
    && find /out/opt/notebook-intelligence -type f \( -name '*.js.map' -o -name '*.css.map' \) -delete \
    && find /out/opt/notebook-intelligence -type d -name __pycache__ -prune -exec rm -rf {} + \
    # Anchored build-time patches (settings refresh + Ollama empty-family context fallback).
    && /opt/conda/bin/python /tmp/patches/patch_nbi.py \
        --bundles "${labext}/static/*.js" \
        --ollama "/out/opt/notebook-intelligence/lib/notebook_intelligence/llm_providers/ollama_llm_provider.py" \
    # JupyterLab discovers the federated extension here without a second copy.
    && install -d -m 0755 /out/usr/local/share/jupyter/labextensions/@plmbr /out/opt/scidesktop/manifest.d \
    && ln -s /opt/notebook-intelligence/lib/notebook_intelligence/labextension \
        /out/usr/local/share/jupyter/labextensions/@plmbr/notebook-intelligence \
    && chmod -R a+rX,go-w /out \
    && PYTHONPATH=/out/opt/notebook-intelligence/lib /opt/conda/bin/python -c \
        'import importlib.metadata as m, json; json.dump({p: m.version(p) for p in ("notebook-intelligence", "litellm", "claude-agent-sdk")}, open("/out/opt/scidesktop/manifest.d/notebook-intelligence.json", "w"))' \
    && cat /out/opt/scidesktop/manifest.d/notebook-intelligence.json

# Integration files from rootfs/ at their image paths, readable and without
# group or other write permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /out/ /

FROM os AS test
COPY --from=coding-agents / /
COPY --from=component / /
COPY --chmod=0755 test.sh /tmp/test.sh
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,from=jupyter-env,source=/usr/local/etc/jupyter,target=/usr/local/etc/jupyter \
    bash /tmp/test.sh
