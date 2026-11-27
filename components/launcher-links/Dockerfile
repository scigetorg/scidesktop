# syntax=docker/dockerfile:1
# Operator-configured external launcher tiles (such as WEBKNOSSOS via
# SCIDESKTOP_WEBKNOSSOS_URL or SCIDESKTOP_LAUNCHER_LINKS) for JupyterLab at
# /opt/launcher-links. Builds a tiny federated JupyterLab extension against
# jupyter-env's JupyterLab and an authenticated server extension outside
# /opt/conda so the component stays self-contained.

# Versions come from docker-bake.hcl.
ARG NODE_VERSION
ARG UBUNTU_IMAGE

FROM docker.io/library/node:${NODE_VERSION}-bookworm-slim AS build
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY labextension /src/labextension
COPY scidesktop_launcher_links /src/scidesktop_launcher_links
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=cache,target=/root/.npm \
    export PATH="${PATH}:/opt/conda/bin" \
    && cd /src/labextension \
    && npm ci --no-audit --no-fund \
    && jupyter-builder build --core-package-file=/opt/conda/share/jupyter/lab/static/package.json . \
    && labextension=/out/opt/launcher-links/lib/share/jupyter/labextensions/scidesktop-launcher-links \
    && install -d -m 0755 /out/opt/launcher-links/lib "$(dirname "${labextension}")" \
    && cp -r /src/scidesktop_launcher_links/. /out/opt/launcher-links/lib/scidesktop_launcher_links/ \
    && mv /src/labextension/labextension "${labextension}" \
    && find /out/opt/launcher-links -name __pycache__ -prune -exec rm -rf {} + \
    && find /out/opt/launcher-links -name "*.map" -delete \
    && test -f "${labextension}/package.json" \
    && install -d -m 0755 /out/usr/local/share/jupyter/labextensions /out/opt/scidesktop/manifest.d \
    && ln -s /opt/launcher-links/lib/share/jupyter/labextensions/scidesktop-launcher-links \
        /out/usr/local/share/jupyter/labextensions/scidesktop-launcher-links \
    && chmod -R a+rX,go-w /out \
    && sha="$(cat /src/scidesktop_launcher_links/handlers.py /src/labextension/lib/index.js | sha256sum | cut -d ' ' -f 1)" \
    && printf '{"launcher-links": "0.1.0", "sha256": "%s"}\n' "${sha}" \
        > /out/opt/scidesktop/manifest.d/launcher-links.json

FROM ${UBUNTU_IMAGE} AS rootfs
COPY rootfs/ /rootfs/
RUN chmod -R a+rX,go-w /rootfs

FROM scratch AS component
COPY --from=rootfs /rootfs/ /
COPY --from=build /out/ /

FROM os AS test
COPY --from=component / /
USER ${NB_UID}
RUN --mount=type=bind,from=jupyter-env,source=/opt/conda,target=/opt/conda \
    --mount=type=bind,from=jupyter-env,source=/etc/jupyter,target=/etc/jupyter \
    --mount=type=bind,from=jupyter-env,source=/usr/local/etc/jupyter,target=/usr/local/etc/jupyter \
    bash -euo pipefail <<'EOF'
work="$(mktemp -d)"
server=""
trap 'if [ -n "${server}" ]; then kill "${server}" 2>/dev/null || true; wait "${server}" 2>/dev/null || true; fi; rm -rf "${work}"' EXIT
export HOME="${work}/home"
mkdir -p "${HOME}"

labs="$(/opt/conda/bin/python -m jupyter labextension list 2>&1)"
printf '%s\n' "${labs}"
grep -q 'scidesktop-launcher-links .*enabled.*OK' <<<"${labs}"

port="$(/opt/conda/bin/python -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
base="/user/links-test/"
SCIDESKTOP_WEBKNOSSOS_URL="https://webknossos.example.org/jh-auth/login" \
SCIDESKTOP_LAUNCHER_LINKS='[{"title":"Docs","url":"https://docs.example.org"},{"title":"Bad","url":"javascript:alert(1)"}]' \
/opt/conda/bin/python -m jupyter lab --no-browser --ip=127.0.0.1 --port="${port}" --ServerApp.port_retries=0 \
    --MCPExtensionApp.mcp_port=0 --ServerApp.base_url="${base}" --IdentityProvider.token=links-test \
    --ServerApp.root_dir="${HOME}" >"${work}/jupyter.log" 2>&1 &
server=$!

ready=0
for _ in $(seq 60); do
    if curl -fsS -o /dev/null "http://127.0.0.1:${port}${base}api/status?token=links-test" 2>/dev/null; then
        ready=1
        break
    fi
    sleep 1
done
if [ "${ready}" -ne 1 ]; then
    tail -n 60 "${work}/jupyter.log"
    exit 1
fi

unauth="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}${base}scidesktop-launcher-links/links")"
case "${unauth}" in
    302|401|403) ;;
    *) echo "expected auth refusal, got ${unauth}"; tail -n 40 "${work}/jupyter.log"; exit 1 ;;
esac

body="$(curl -fsS -H 'Authorization: token links-test' "http://127.0.0.1:${port}${base}scidesktop-launcher-links/links")"
printf '%s\n' "${body}"
/opt/conda/bin/python -c 'import json, sys; links = json.loads(sys.argv[1])["links"]; assert [l["title"] for l in links] == ["WEBKNOSSOS", "Docs"], links; assert links[0]["url"] == "https://webknossos.example.org/jh-auth/login"; assert links[0]["icon"] == "webknossos"' "${body}"
# Edge-case unit checks: unset env, malformed IPv6/port URLs, and duplicate ID collisions.
/opt/conda/bin/python - <<'PY'
import json, sys
sys.path.append("/opt/launcher-links/lib")
from scidesktop_launcher_links.handlers import collect_links

assert collect_links(environ={}) == []
items = [
    {"title": "BadIPv6", "url": "https://[::1"},
    {"title": "BadPort", "url": "https://example.org:notaport"},
    {"title": "Docs-2", "url": "https://docs2.example.org"},
    {"title": "Docs", "url": "https://docs1.example.org"},
    {"title": "Docs", "url": "https://docs3.example.org"},
]
out = collect_links(environ={"SCIDESKTOP_LAUNCHER_LINKS": json.dumps(items)})
ids = [x["id"] for x in out]
assert len(ids) == len(set(ids)) == 3, out
assert [x["url"] for x in out] == [
    "https://docs2.example.org",
    "https://docs1.example.org",
    "https://docs3.example.org",
], out
PY
test -r /opt/scidesktop/manifest.d/launcher-links.json
EOF
