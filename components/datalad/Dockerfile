# syntax=docker/dockerfile:1
# DataLad and git-annex in an isolated venv at /opt/datalad (backed by
# jupyter-env's Python 3.13 so no second conda runtime is shipped), with the
# commands on PATH. Included in scidesktop (docs/images.md).

ARG UBUNTU_IMAGE
FROM ${UBUNTU_IMAGE} AS build
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get install --no-install-recommends -y ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
# A pin changed without ./lock fails here rather than installing the old lock.
RUN --mount=type=bind,from=components,source=check-lock,target=/usr/local/bin/check-lock \
    --mount=type=bind,source=.,target=/src \
    check-lock /src/requirements.in /src/requirements.lock
COPY requirements.lock /tmp/
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,from=components,source=trim-python-env,target=/usr/local/bin/trim-python-env \
    /opt/conda/bin/python -m venv --without-pip /opt/datalad \
    && /opt/conda/bin/python -m pip --python /opt/datalad/bin/python install \
        --no-cache-dir --no-deps --require-hashes --no-compile -r /tmp/requirements.lock \
    # git-annex is AGPL and its wheel carries no licence text: add the text
    # from the source of this version, and where that source is.
    && annex="$(/opt/datalad/bin/python -c 'import importlib.metadata as m; print(m.version("git-annex"))')" \
    && install -d -m 0755 /opt/datalad/licenses \
    && curl -fsSL --retry 5 --retry-delay 5 --retry-connrefused -o /opt/datalad/licenses/git-annex-AGPL \
        "https://raw.githubusercontent.com/datalad/git-annex/${annex}/doc/license/AGPL" \
    && grep -q "GNU AFFERO GENERAL PUBLIC LICENSE" /opt/datalad/licenses/git-annex-AGPL \
    && printf '%s\n' "git-annex ${annex}, AGPL-3.0-or-later, unmodified, as published at" \
        "https://pypi.org/project/git-annex/${annex}/ by its upstream." \
        "Source of this version: https://git-annex.branchable.com/install/fromsource/" \
        "(git://git-annex.branchable.com/, tag ${annex}); a mirror is at" \
        "https://github.com/datalad/git-annex/tree/${annex}" > /opt/datalad/licenses/git-annex-SOURCE \
    && trim-python-env /opt/datalad \
    && chmod -R a+rX,go-w /opt/datalad \
    && install -d -m 0755 /out/manifest \
    && /opt/datalad/bin/python -c 'import json, importlib.metadata as m; json.dump({p: m.version(p) for p in ("datalad", "datalad-container", "datalad-osf", "osfclient", "git-annex")}, open("/out/manifest/datalad.json", "w"))' \
    && cat /out/manifest/datalad.json

# Integration files from rootfs/ (the command links) at their image paths,
# without group or other write permission whatever the checkout's umask.
FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /opt/datalad /opt/datalad
COPY --from=build /out/manifest/ /opt/scidesktop/manifest.d/

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,source=test.sh,target=/tmp/test.sh bash /tmp/test.sh
