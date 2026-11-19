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
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get install --no-install-recommends -y ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# A pin changed without ./lock fails here rather than installing the old lock.
RUN --mount=type=bind,from=components,source=check-lock,target=/usr/local/bin/check-lock \
    --mount=type=bind,source=.,target=/src \
    check-lock /src/environment.yml /src/linux-64.lock \
    && check-lock /src/requirements.in /src/requirements.lock
COPY --from=micromamba /usr/local/bin/micromamba /usr/local/bin/micromamba
COPY linux-64.lock requirements.lock /tmp/
COPY patches/ /tmp/patches/
RUN micromamba create --yes --root-prefix /opt/conda --prefix /opt/conda \
        --file /tmp/linux-64.lock \
    # Keep users' installs on this Python minor, as docker-stacks does.
    && /opt/conda/bin/python -c 'import sys; print(f"python {sys.version_info[0]}.{sys.version_info[1]}.*")' \
        >> /opt/conda/conda-meta/pinned \
    && printf '%s\n' 'auto_update_conda: false' 'show_channel_urls: true' \
        'channels:' '  - conda-forge' > /opt/conda/.condarc \
    # Extensions only on PyPI: hashed, without dependencies (they come from the
    # conda lock above).
    && /opt/conda/bin/python -m pip install --no-cache-dir --no-deps --require-hashes \
        -r /tmp/requirements.lock \
    # Startup-time patches; see each file.
    && for p in /tmp/patches/*.py; do /opt/conda/bin/python "${p}"; done \
    && /opt/conda/bin/python -m compileall -q /opt/conda/lib/python3*/site-packages/rfc3987_syntax \
        /opt/conda/lib/python3*/site-packages/simpervisor \
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
    && /opt/conda/bin/python -c 'import json, glob; v = {m["name"]: m["version"] for m in map(lambda f: json.load(open(f)), glob.glob("/opt/conda/conda-meta/*.json"))}; json.dump({k: v.get(k) for k in ("python", "jupyterlab", "jupyterhub-singleuser", "jupyter-server-proxy", "ipykernel", "mamba", "ipywidgets", "jupyterlab-git")}, open("/out/manifest/jupyter-env.json", "w"))' \
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
    && python -c 'import jupyter_server_proxy, ipykernel, jupyterlab, ipywidgets, jupyterlab_git, jupyterlmod' \
    && pip check \
    && mamba --version \
    && ! command -v conda \
    && test -r /opt/conda/etc/profile.d/mamba.sh \
    && touch /opt/conda/.write-test && rm /opt/conda/.write-test \
    && exts=$(jupyter server extension list 2>&1) \
    && for e in jupyter_server_proxy jupyterlab_git jupyterlmod; do \
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
    && us=$(cd /tmp && python -X importtime -c 'import jsonschema' 2>&1 \
            | awk -F'|' '/rfc3987_syntax.syntax_helpers/ { gsub(/ /, "", $2); print $2 }') \
    && echo "rfc3987_syntax import: ${us:-0} us" && [ "${us:-0}" -lt 200000 ] \
    # The desktop's readiness poll is capped (patches/simpervisor_ready_backoff.py).
    && python -c 'import inspect, simpervisor.process as p; assert "min(2 * wait_time, 0.1)" in inspect.getsource(p)'
