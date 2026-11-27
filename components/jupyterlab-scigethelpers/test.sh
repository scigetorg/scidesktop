#!/bin/bash
# Component test for jupyterlab-scigethelpers: verifies federated labextension
# registration, starts a real Jupyter server under a nested base_url using the
# actual /usr/local/etc/jupyter/jupyter_server_config.py loader, and exercises
# auth, Origin/XSRF protections, overview/info/check/cite APIs, and permissions.
set -euo pipefail
python=/opt/conda/bin/python
work="$(mktemp -d)"
server=""
trap '[ -z "${server}" ] || { kill "${server}" 2>/dev/null; wait "${server}" 2>/dev/null; } || true; rm -rf "${work}" || true' EXIT

export HOME="${work}/home"
mkdir -p "${HOME}"

# JupyterLab discovers the federated extension under /usr/local/share/jupyter/labextensions.
"${python}" -m jupyter labextension list >"${work}/labextensions" 2>&1
grep -A 40 '^/usr/local/share/jupyter/labextensions' "${work}/labextensions" \
    | grep -q 'jupyterlab-scigethelpers.*enabled.*OK' \
    || { cat "${work}/labextensions"; exit 1; }

# Seed a synthetic module usage log + local catalogue so POST /cite works offline.
mkdir -p "${HOME}/.local/state/scigethelpers" "${HOME}/.config/sciget"
printf 'smoketool\t1.2\t2026-11-27T00:00:00Z\n' > "${HOME}/.local/state/scigethelpers/module-usage.tsv"
cat > "${HOME}/apps.json" <<'JSON'
{"smoketool": {"apps": {"smoketool 1.2": {"version": "20260101", "exec": "", "image": "smoketool_1.2"}},
               "categories": ["programming"], "citation": "Smoke, A. (2026). A tool. https://doi.org/10.0000/smoke"}}
JSON
export SCIGETHELPERS_CITE_CATALOGUE_URL="file://${HOME}/apps.json"

base=/user/helpers-test/
port="$("${python}" -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
"${python}" -m jupyter lab --no-browser --ip=127.0.0.1 --port="${port}" --ServerApp.port_retries=0 \
    --MCPExtensionApp.mcp_port=0 \
    --ServerApp.base_url="${base}" --IdentityProvider.token=helpers-test --ServerApp.root_dir="${HOME}" \
    >"${work}/jupyter.log" 2>&1 &
server=$!
for _ in $(seq 60); do
    if curl -fsS -o /dev/null "http://127.0.0.1:${port}${base}api/status?token=helpers-test" 2>/dev/null; then break; fi
    sleep 1
done

"${python}" /tmp/jupyterlab-scigethelpers-check.py "http://127.0.0.1:${port}${base}" helpers-test \
    || { grep -v "Skipped non-installed" "${work}/jupyter.log" | tail -n 100; exit 1; }

# Nothing root-owned is writable by group or others, and the user can read it all.
if find /opt/jupyterlab-scigethelpers /usr/local/share/jupyter/labextensions/jupyterlab-scigethelpers \
        /etc/scidesktop/jupyter_server_config.d/jupyterlab-scigethelpers.py \
        ! -type l \( -perm /022 -o ! -readable \) -print | grep .; then
    echo "bad permissions on the files above" >&2
    exit 1
fi
echo "jupyterlab-scigethelpers: labextension and API work"
