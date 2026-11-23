#!/bin/bash
# End-to-end check of an image that copies the datascience-env component.
#
#   ./test/datascience-env-smoke.sh [image]
#
# Verifies:
#   - `datascience` kernel is registered and executes Polars, PyArrow, DuckDB
#     (+ SQLAlchemy/duckdb-engine), scikit-learn, XGBoost, LightGBM,
#     statsmodels, SHAP, Optuna, Plotly, Altair, and JupySQL
#   - Default `python3` kernel remains on /opt/conda

set -uo pipefail

IMAGE="${1:-datadesktop}"
NAME="datascience-env-smoke-$$"
TOKEN="datascience-smoke"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() {
    docker logs "${NAME}" >"/tmp/${NAME}.log" 2>&1 || true
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "datascience-env smoke: ${IMAGE}"
docker run -d --name "${NAME}" --shm-size=2g -e JUPYTER_TOKEN="${TOKEN}" \
    "${IMAGE}" start-notebook.py >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }

ready=0
for _ in $(seq 1 120); do
    if docker exec "${NAME}" curl -fsS --max-time 10 -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null; then
        ready=1
        break
    fi
    sleep 1
done
if [ "${ready}" -ne 1 ]; then
    fail "notebook server did not become ready within 120s"
    exit 1
fi

docker exec -i "${NAME}" /opt/conda/bin/python - "${TOKEN}" <<'PY' && pass "datascience kernel (Polars, DuckDB, Parquet, XGBoost, LightGBM, SHAP, Optuna) passed" || fail "datascience kernel (Polars, DuckDB, Parquet, XGBoost, LightGBM, SHAP, Optuna) passed"
import json
import sys
import urllib.request
import uuid
import websocket

token = sys.argv[1]
base = "http://127.0.0.1:8888"
headers = {"Authorization": f"token {token}"}

def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(base + path, data=data, method=method, headers=headers)
    if data is not None:
        r.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(r, timeout=30) as resp:
        raw = resp.read()
        return json.loads(raw) if raw else None

specs = req("GET", "/api/kernelspecs")["kernelspecs"]
assert "datascience" in specs, f"missing datascience kernel: {list(specs)}"
assert specs["python3"]["spec"]["argv"][0].startswith("/opt/conda/"), specs["python3"]["spec"]["argv"]

def run_code(kernel_name, code):
    k = req("POST", "/api/kernels", {"name": kernel_name})
    kid = k["id"]
    try:
        ws = websocket.create_connection(
            f"ws://127.0.0.1:8888/api/kernels/{kid}/channels?token={token}",
            timeout=120,
        )
        msg_id = uuid.uuid4().hex
        ws.send(json.dumps({
            "header": {
                "msg_id": msg_id,
                "username": "smoke",
                "session": uuid.uuid4().hex,
                "msg_type": "execute_request",
                "version": "5.3",
            },
            "parent_header": {},
            "metadata": {},
            "content": {
                "code": code,
                "silent": False,
                "store_history": False,
                "user_expressions": {},
                "allow_stdin": False,
            },
            "buffers": [],
            "channel": "shell",
        }))
        out, err = [], []
        while True:
            msg = json.loads(ws.recv())
            if msg.get("parent_header", {}).get("msg_id") != msg_id:
                continue
            mtype = msg["msg_type"]
            if mtype == "stream":
                out.append(msg["content"]["text"])
            elif mtype == "error":
                err.append(f'{msg["content"]["ename"]}: {msg["content"]["evalue"]}')
            elif mtype == "status" and msg["content"]["execution_state"] == "idle":
                break
        ws.close()
        if err:
            raise AssertionError("; ".join(err))
        return "".join(out).strip()
    finally:
        req("DELETE", f"/api/kernels/{kid}")

ds_out = run_code("datascience", """
import pathlib, site, sys, tempfile
import numpy as np
import pandas as pd
import polars as pl
import pyarrow as pa
import duckdb, sqlalchemy, sql, scipy, statsmodels, xgboost as xgb, lightgbm as lgb
import optuna, shap, matplotlib, seaborn, plotly, altair, watermark
from sklearn.linear_model import Ridge

assert sys.executable.startswith("/opt/datascience-env/"), sys.executable
assert site.ENABLE_USER_SITE is False, f"expected user site disabled, got {site.ENABLE_USER_SITE}"
work = pathlib.Path(tempfile.mkdtemp())

# Polars -> Parquet -> DuckDB + SQLAlchemy roundtrip
df = pl.DataFrame({"x": [1.0, 2.0, 3.0, 4.0], "y": [2.0, 4.0, 6.0, 8.0]})
pq = work / "data.parquet"
df.write_parquet(pq)
con = duckdb.connect()
total = con.execute(f"SELECT sum(y) FROM read_parquet('{pq}')").fetchone()[0]
assert total == 20.0, total
eng = sqlalchemy.create_engine("duckdb:///:memory:")
with eng.connect() as conn:
    assert conn.execute(sqlalchemy.text("SELECT 42")).scalar() == 42

# Fit quick models with scikit-learn, XGBoost, LightGBM
X = np.array([[1.0, 0.0], [2.0, 1.0], [3.0, 0.0], [4.0, 1.0]])
y = np.array([1.0, 2.0, 3.0, 4.0])
Ridge().fit(X, y)
xgb.XGBRegressor(n_estimators=2, max_depth=2).fit(X, y)
lgb.LGBMRegressor(n_estimators=2, min_child_samples=1, verbose=-1).fit(X, y)
print("DS_OK", total, pl.__version__, duckdb.__version__)
""")
assert "DS_OK 20.0" in ds_out, ds_out

base_out = run_code("python3", "import sys; print(sys.executable)")
assert base_out.startswith("/opt/conda/"), base_out
PY

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "datascience-env smoke: all checks passed"
else
    echo "datascience-env smoke: ${FAILED} check(s) failed; container log at /tmp/${NAME}.log"
fi
exit "${FAILED}"
