#!/bin/bash
# The component's own test: runs on the OS layer as the notebook user, with
# nothing from the base image but the OS.
set -euo pipefail
env=/opt/ai-ready/env/bin
airflow=/opt/ai-ready/airflow/bin
content=/etc/scidesktop/home-defaults/ai-ready
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

"${env}/python" -c 'import ipykernel, mlflow, pandas, plotly, psycopg2, shap, sklearn, skops'
"${env}/mlflow" --version
AIRFLOW_HOME="${work}/airflow" "${airflow}/airflow" version
"${airflow}/python" -c 'import airflow.providers.postgres, mlflow, psycopg2, sklearn'
"${env}/python" -m pip check
"${env}/python" -m pip --python "${airflow}/python" check

# PostgreSQL creates a cluster and serves it as the notebook user.
"${env}/initdb" -D "${work}/pg" -U aiready --encoding=UTF8 --locale=C >/dev/null
"${env}/pg_ctl" -D "${work}/pg" -w -o "-h 127.0.0.1 -p 55432 -k ${work}" start >/dev/null
"${env}/psql" -h "${work}" -p 55432 -U aiready -d postgres -Atc 'select version()'
"${env}/pg_ctl" -D "${work}/pg" -w -m fast stop >/dev/null

# The kernelspec is valid and its interpreter exists; every seeded notebook
# asks for it.
"${env}/python" - "${content}" <<'PYTHON'
import json, os, pathlib, sys
spec = json.load(open("/opt/ai-ready/share/jupyter/kernels/ai-ready/kernel.json"))
assert os.access(spec["argv"][0], os.X_OK), spec["argv"]
assert spec["env"]["PYTHONPATH"] == "${HOME}/ai-ready/src", spec["env"]
notebooks = sorted(pathlib.Path(sys.argv[1], "notebooks").glob("*.ipynb"))
assert notebooks
for notebook in notebooks:
    assert json.load(open(notebook))["metadata"]["kernelspec"]["name"] == "ai-ready", notebook
json.load(open("/opt/scidesktop/manifest.d/ai-ready.json"))
print(spec["display_name"], "-", len(notebooks), "notebooks")
PYTHON
grep -q '"sklearn.tree._tree.Tree"' "${content}/src/vep_pipeline.py"
test -s /opt/ai-ready/upstream/REVISION -a -f /opt/ai-ready/upstream/variables.json \
    -a -f /opt/ai-ready/upstream/icons/airflow.svg -a -f /opt/ai-ready/upstream/icons/mlflow.svg

# The hook parses, and the supervisor prints the exports the hook evaluates.
bash -n /usr/local/bin/before-notebook.d/40-ai-ready.sh
test -x /usr/local/bin/before-notebook.d/40-ai-ready.sh
JUPYTERHUB_SERVICE_PREFIX=/user/x/ "${env}/python" /opt/ai-ready/lib/ai_ready_services.py env \
    | grep -qx "export MLFLOW_TRACKING_URI=http://127.0.0.1:5000/user/x/mlflow"
"${env}/python" -c 'import ast, sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]' \
    /opt/ai-ready/etc/jupyter/jupyter_server_config.py /opt/ai-ready/lib/ai_ready_dashboard.py

# Nothing root-owned is writable by group or others, and the user can read it all.
if find /opt/ai-ready "${content}" /usr/local/bin/before-notebook.d/40-ai-ready.sh \
        ! -type l \( -perm /022 -o ! -readable \) -print | grep .; then
    echo "bad permissions on the files above" >&2
    exit 1
fi
