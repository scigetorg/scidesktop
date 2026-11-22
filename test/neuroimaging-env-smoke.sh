#!/bin/bash
# End-to-end check of an image that copies the neuroimaging-env component.
#
#   ./test/neuroimaging-env-smoke.sh [image]
#
# Starts a notebook server and executes a real cell on the `neuroimaging`
# kernel over Jupyter's WebSocket API, verifying the neuroimaging Python stack
# and ipyniivue widget instantiation while keeping the default python3 kernel
# on /opt/conda.

set -uo pipefail

IMAGE="${1:-neurodesktop}"
NAME="neuroimaging-env-smoke-$$"
TOKEN="neuroimaging-smoke"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() {
    docker logs "${NAME}" >"/tmp/${NAME}.log" 2>&1 || true
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "neuroimaging-env smoke: ${IMAGE}"
docker run -d --name "${NAME}" --shm-size=2g -e JUPYTER_TOKEN="${TOKEN}" \
    "${IMAGE}" start-notebook.py >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }

for _ in $(seq 1 120); do
    docker exec "${NAME}" curl -fsS -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null && break
    sleep 1
done

docker exec -i "${NAME}" /opt/conda/bin/python - "${TOKEN}" <<'PY' && pass "neuroimaging kernel executes neuroimaging stack & ipyniivue" || fail "neuroimaging kernel executes neuroimaging stack & ipyniivue"
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
assert "neuroimaging" in specs, f"missing neuroimaging kernel: {list(specs)}"
assert specs["python3"]["spec"]["argv"][0].startswith("/opt/conda/"), specs["python3"]["spec"]["argv"]

def run_code(kernel_name, code):
    k = req("POST", "/api/kernels", {"name": kernel_name})
    kid = k["id"]
    try:
        ws = websocket.create_connection(
            f"ws://127.0.0.1:8888/api/kernels/{kid}/channels?token={token}",
            timeout=60,
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

neuro_out = run_code("neuroimaging", """
import sys, shutil
import numpy as np
import nibabel as nib
import nipype, niwrap, pydra, nipoppy, ipyniivue, datalad, datalad_osf, osfclient, matplotlib, scipy, pandas, watermark, xnat
img = nib.Nifti1Image(np.ones((4, 4, 4), dtype=np.float32), np.eye(4))
nv = ipyniivue.NiiVue()
assert sys.executable.startswith("/opt/neuroimaging-env/"), sys.executable
assert shutil.which("git") is not None, "PATH lost system binaries"
print("NEURO_OK", img.shape, type(nv).__name__)
""")
assert "NEURO_OK (4, 4, 4) NiiVue" in neuro_out, neuro_out

base_out = run_code("python3", "import sys; print(sys.executable)")
assert base_out.startswith("/opt/conda/"), base_out
PY

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "neuroimaging-env smoke: all checks passed"
else
    echo "neuroimaging-env smoke: ${FAILED} check(s) failed; container log at /tmp/${NAME}.log"
fi
exit "${FAILED}"
