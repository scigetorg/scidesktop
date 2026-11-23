# syntax=docker/dockerfile:1
# The Jupyter server environment at /opt/conda, installed from a lockfile.
# Group-writable with setgid directories; the assembly copies it owned by the
# notebook user, so `mamba install` works for the default user and for a
# remapped NB_UID in group NB_GID.

# Built from the plain Ubuntu image, not the OS layer: the output depends only
# on the lockfiles, so OS updates do not rebuild it or change its layer.
ARG UBUNTU_IMAGE
FROM ${UBUNTU_IMAGE} AS build
ARG NB_UID
ARG NB_GID
ARG TARGETARCH
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get install --no-install-recommends -y ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# A pin changed without ./lock fails here rather than installing the old lock.
RUN --mount=type=bind,from=components,source=check-lock,target=/usr/local/bin/check-lock \
    --mount=type=bind,source=.,target=/src \
    check-lock /src/environment.yml /src/linux-*.lock \
    && check-lock /src/requirements.in /src/requirements.lock
COPY --from=micromamba /usr/local/bin/micromamba /usr/local/bin/micromamba
COPY linux-*.lock requirements.lock /tmp/
COPY patches/ /tmp/patches/
RUN --mount=type=bind,from=components,source=target-arch,target=/usr/local/bin/target-arch \
    --mount=type=bind,from=components,source=trim-python-env,target=/usr/local/bin/trim-python-env \
    micromamba create --yes --root-prefix /opt/conda --prefix /opt/conda \
        --file "/tmp/$(target-arch conda).lock" \
    # Keep users' installs on this Python minor, as docker-stacks does.
    && /opt/conda/bin/python -c 'import sys; print(f"python {sys.version_info[0]}.{sys.version_info[1]}.*")' \
        >> /opt/conda/conda-meta/pinned \
    && printf '%s\n' 'auto_update_conda: false' 'show_channel_urls: true' \
        'channels:' '  - conda-forge' > /opt/conda/.condarc \
    # Extensions only on PyPI: hashed, without dependencies (they come from the
    # conda lock above).
    && /opt/conda/bin/python -m pip install --no-cache-dir --no-deps --require-hashes \
        --no-compile -r /tmp/requirements.lock \
    # Register the Bash kernel in /opt/conda/share/jupyter/kernels/bash.
    && /opt/conda/bin/python -m bash_kernel.install --sys-prefix \
    # Startup-time patches; see each file.
    && for p in /tmp/patches/*.py; do /opt/conda/bin/python "${p}" || exit 1; done \
    # RISE pulls in the legacy JupyterLab 3 mathjax3-extension; JupyterLab 4 ships MathJax natively.
    && rm -rf /opt/conda/share/jupyter/labextensions/@jupyterlab/mathjax3-extension \
    && MAMBA_ROOT_PREFIX=/opt/conda micromamba clean --all --force-pkgs-dirs --yes \
    && /opt/conda/bin/jupyter lab clean \
    # Disabled JupyterLab plugins live in the environment. The server settings
    # are in rootfs/etc/jupyter, the lowest-priority config folder, so an
    # operator's or derived image's settings in any other folder win.
    && /opt/conda/bin/jupyter labextension disable --level=sys_prefix \
        '@jupyterlab/apputils-extension:announcements' \
        '@jupyterlab/extensionmanager-extension:plugin' \
        '@jupyterlab/help-extension:about' \
    && install -d -m 0755 /out/manifest \
    && /opt/conda/bin/python -c 'import importlib.metadata as im, json, glob; v = {m["name"]: m["version"] for m in map(lambda f: json.load(open(f)), glob.glob("/opt/conda/conda-meta/*.json"))}; d = {k: v.get(k) for k in ("python", "jupyterlab", "jupyterhub-singleuser", "jupyter-server-proxy", "ipykernel", "mamba", "ipywidgets", "anywidget", "ipycanvas", "jupyterlab-git", "jupyter-resource-usage", "jupyterlab_rise", "jupyter-scheduler", "nbgitpuller", "papermill", "pytest", "uv", "jupyter-ai")}; d["bash_kernel"] = im.version("bash_kernel"); json.dump(d, open("/out/manifest/jupyter-env.json", "w"))' \
    && trim-python-env /opt/conda \
    && chown -R "${NB_UID:?}:${NB_GID:?}" /opt/conda \
    && chmod -R g+rwX /opt/conda \
    && find /opt/conda -type d -exec chmod g+s {} +

# Integration files from rootfs/ (hooks, symlinks, config) at their image paths,
# without group or other write permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R go-w /rootfs

# /opt/conda is owned by the notebook user so `mamba install` works. Copying
# /opt/ keeps that ownership on /opt/conda itself (a COPY's destination
# directory would be created as root).
FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /opt/ /opt/
COPY --from=build /out/manifest/ /opt/scidesktop/manifest.d/

FROM os AS test
COPY --from=component / /
ENV PATH=/opt/conda/bin:${PATH}
USER ${NB_UID}
RUN set -e \
    && jupyter lab --version \
    && jupyterhub-singleuser --version \
    && python -c 'import jupyter_server_proxy, ipykernel, jupyterlab, ipywidgets, anywidget, ipycanvas, jupyterlab_git, jupyterlmod, jupyter_resource_usage, jupyter_scheduler, nbgitpuller, papermill, bash_kernel, jupyter_ai_acp_client, jupyterlab_chat, fastmcp; import importlib.metadata as im; assert tuple(int(p) for p in im.version("fastmcp").split(".")[:3]) >= (3, 4, 10), im.version("fastmcp")' \
    && pip check \
    && mamba --version \
    && uv --version \
    && papermill --version \
    && pytest --version \
    && jupyter kernelspec list 2>&1 | grep -qw bash \
    && ! test -e /opt/conda/bin/bash \
    && ! test -e /opt/conda/share/jupyter/labextensions/@jupyterlab/mathjax3-extension \
    && ! command -v conda \
    && test -r /opt/conda/etc/profile.d/mamba.sh \
    && touch /opt/conda/.write-test && rm /opt/conda/.write-test \
    && exts=$(jupyter server extension list 2>&1) \
    && for e in jupyter_server_proxy jupyterlab_git jupyterlmod jupyter_resource_usage jupyter_scheduler nbgitpuller jupyter_ai_acp_client jupyter_ai_persona_manager jupyter_ai_router jupyterlab_chat jupyter_live_content; do \
         echo "${exts}" | grep -q "${e}.*enabled" || { echo "server extension ${e} not enabled"; exit 1; }; \
       done \
    # The server settings are loaded, not just installed.
    && cfg=$(jupyter server --show-config 2>/dev/null) \
    && echo "${cfg}" | grep -q 'allow_hidden = True' \
    && echo "${cfg}" | grep -q "terminado_settings = {'shell_command': \['/bin/bash', '-l'\]}" \
    && echo "${cfg}" | grep -q 'check_for_updates_class = .*NeverCheckForUpdate' \
    && test ! -d /opt/conda/pkgs -o -z "$(ls -A /opt/conda/pkgs 2>/dev/null | grep -v -E '^(cache|urls|urls.txt)$')" \
    && jupyter server extension list 2>&1 | grep -E 'enabled|disabled' \
    # rfc3987_syntax must not compile its parsers at import (patches/).
    && python -c 'import rfc3987_syntax.syntax_helpers as h; assert not hasattr(h, "_LazyLark") or h.syntax_parser._parser is None' \
    && us=$(cd /tmp && python -X importtime -c 'import jsonschema' 2>&1 \
            | awk -F'|' '/rfc3987_syntax.syntax_helpers/ { gsub(/ /, "", $2); print $2 }') \
    && echo "rfc3987_syntax import: ${us:-0} us" && [ "${us:-0}" -lt 750000 ] \
    # JupyterLab extensions (Jupyter AI, RISE, scheduler, resource usage, widgets) are compatible.
    && labs=$(jupyter labextension list 2>&1) \
    && for e in '@jupyter-ai/acp-client' '@jupyter-ai/persona-manager' jupyterlab-chat-extension '@jupyter-server/resource-usage' jupyterlab-rise '@jupyterlab/scheduler' anywidget ipycanvas; do \
         echo "${labs}" | grep -q "${e} .*enabled.*OK" || { echo "JupyterLab extension ${e} not OK"; exit 1; }; \
       done \
    && python -c 'import pathlib, jupyter_ai_acp_client as c; d = pathlib.Path(c.__file__).parent; assert "scidesktop-acp-per-event-debug-log" in (d / "default_acp_client.py").read_text(); assert "scidesktop-acp-opencode-2" in (d / "acp_personas/opencode.py").read_text()' \
    && python -c 'import inspect, jupyterlab_rise.app as a; assert "scidesktop-rise-extension-isolation" in inspect.getsource(a)' \
    # The desktop's readiness poll is capped (patches/simpervisor_ready_backoff.py).
    && python -c 'import inspect, simpervisor.process as p; assert "min(2 * wait_time, 0.1)" in inspect.getsource(p)' \
    # Execute a real Bash kernel cell and a Papermill notebook end-to-end.
    && python -c 'import json, tempfile, subprocess, pathlib; d = pathlib.Path(tempfile.mkdtemp()); nb = {"cells": [{"cell_type": "code", "execution_count": None, "metadata": {}, "outputs": [], "source": ["echo BASH_KERNEL_OK\n"]}], "metadata": {"kernelspec": {"display_name": "Bash", "language": "bash", "name": "bash"}}, "nbformat": 4, "nbformat_minor": 5}; src = d / "in.ipynb"; dst = d / "out.ipynb"; src.write_text(json.dumps(nb)); subprocess.run(["papermill", "--no-progress-bar", str(src), str(dst)], check=True); out = json.loads(dst.read_text()); assert "BASH_KERNEL_OK" in "".join("".join(o.get("text", "")) for o in out["cells"][0]["outputs"]), out'
