#!/bin/bash
# End-to-end check of an image that copies the neuroimaging-env component.
#
#   ./test/neuroimaging-env-smoke.sh [image]
#
# Verifies:
#   - Neuroimaging CLI tools (nf-core, nipoppy, bosh, nipypecli, osf) on PATH
#   - Patched ipyniivue shared frontend bundle served behind Jupyter's login
#   - `neuroimaging` kernel executes neuroimaging stack, ipyniivue, and a local
#     DataLad create/save/get roundtrip using shared git-annex
#   - Default `python3` kernel remains on /opt/conda
#   - Domain EESSI desktop launcher tile (app-eessi-r-bioconductor) registers when EESSI is mounted

set -uo pipefail

IMAGE="${1:-neurodesktop}"
NAME="neuroimaging-env-smoke-$$"
TOKEN="neuroimaging-smoke"
EESSI_STUB=""
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() {
    docker logs "${NAME}" >"/tmp/${NAME}.log" 2>&1 || true
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
    [ -z "${EESSI_STUB}" ] || rm -rf "${EESSI_STUB}"
}
trap cleanup EXIT

EESSI_STUB="$(mktemp -d)"
chmod 0755 "${EESSI_STUB}"

echo "neuroimaging-env smoke: ${IMAGE}"
docker run -d --name "${NAME}" --shm-size=2g -e JUPYTER_TOKEN="${TOKEN}" \
    -v "${EESSI_STUB}:/cvmfs/software.eessi.io/init/modules:ro" \
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

docker exec -u jovyan "${NAME}" bash -lc '
    set -euo pipefail
    nf-core --version >/dev/null
    nipoppy --version >/dev/null
    bosh version >/dev/null
    nipypecli --help >/dev/null
    osf --version >/dev/null
' 2>/dev/null && pass "neuroimaging CLIs (nf-core, nipoppy, bosh, nipypecli, osf) available on PATH" \
    || fail "neuroimaging CLIs (nf-core, nipoppy, bosh, nipypecli, osf) available on PATH"

docker exec -i "${NAME}" /opt/conda/bin/python - "${TOKEN}" <<'PY' && pass "neuroimaging kernel, DataLad roundtrip, and patched ipyniivue asset passed" || fail "neuroimaging kernel, DataLad roundtrip, and patched ipyniivue asset passed"
import json
import pathlib
import sys
import urllib.error
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

# Verify patched ipyniivue shared bundle is served behind auth and refused without it.
assets = list(pathlib.Path("/opt/neuroimaging-env/static").glob("scidesktop-ipyniivue.*.js"))
assert len(assets) == 1, assets
asset_path = f"/neuroimaging-ipyniivue/{assets[0].name}"
r_auth = urllib.request.Request(base + asset_path, headers=headers)
with urllib.request.urlopen(r_auth, timeout=15) as resp:
    assert resp.status == 200
    assert "javascript" in resp.headers.get("Content-Type", "")
    body = resp.read().decode("utf-8", errors="replace")
    assert "createWidgetDefinition" in body and "scidesktop-ipyniivue-model-cleanup" in body

class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

no_redirect = urllib.request.build_opener(_NoRedirect)
try:
    with no_redirect.open(base + asset_path, timeout=15) as resp:
        assert resp.status in (302, 401, 403), f"unauthenticated asset returned {resp.status}"
except urllib.error.HTTPError as exc:
    assert exc.code in (302, 401, 403), f"unauthenticated asset returned {exc.code}"

specs = req("GET", "/api/kernelspecs")["kernelspecs"]
assert "neuroimaging" in specs, f"missing neuroimaging kernel: {list(specs)}"
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

neuro_out = run_code("neuroimaging", """
import pathlib, shutil, site, subprocess, sys, tempfile
import numpy as np
import nibabel as nib
import nipype, niwrap, pydra, nipoppy, ipyniivue, datalad, datalad_osf, osfclient, matplotlib, scipy, pandas, watermark, xnat
img = nib.Nifti1Image(np.ones((4, 4, 4), dtype=np.float32), np.eye(4))
nv = ipyniivue.NiiVue()
assert "scidesktop-ipyniivue-shared-bundle" in (pathlib.Path(ipyniivue.__file__).parent / "static/widget.js").read_text()
assert sys.executable.startswith("/opt/neuroimaging-env/"), sys.executable
assert site.ENABLE_USER_SITE is False, f"expected user site disabled, got {site.ENABLE_USER_SITE}"
assert shutil.which("git-annex") is not None, "PATH lost git-annex"
work = pathlib.Path(tempfile.mkdtemp())
subprocess.run(["git", "config", "--global", "user.name", "smoke"], check=True)
subprocess.run(["git", "config", "--global", "user.email", "smoke@example.invalid"], check=True)
from datalad import api as dl
ds = dl.create(str(work / "origin"), result_renderer="disabled")
(work / "origin" / "data.bin").write_bytes(b"neuro-datalad-ok")
dl.save(dataset=ds, message="add", result_renderer="disabled")
clone = dl.clone(source=str(work / "origin"), path=str(work / "clone"), result_renderer="disabled")
dl.get(dataset=clone, path=str(work / "clone" / "data.bin"), result_renderer="disabled")
assert (work / "clone" / "data.bin").read_bytes() == b"neuro-datalad-ok"
print("NEURO_OK", img.shape, type(nv).__name__)
""")
assert "NEURO_OK (4, 4, 4) NiiVue" in neuro_out, neuro_out

base_out = run_code("python3", "import sys; print(sys.executable)")
assert base_out.startswith("/opt/conda/"), base_out
PY

servers="$(docker exec "${NAME}" curl -fsS -H "Authorization: token ${TOKEN}" \
    "http://127.0.0.1:8888/server-proxy/servers-info" 2>/dev/null || true)"
if grep -q '"app-eessi-r-bioconductor"' <<<"${servers}"; then
    pass "JupyterLab launcher registers app-eessi-r-bioconductor when EESSI is mounted"
else
    fail "JupyterLab launcher registers app-eessi-r-bioconductor when EESSI is mounted"
fi
bad_execs="$(docker exec "${NAME}" bash -c '
    for f in /etc/scidesktop/eessi-apps.d/*.desktop; do
        [ -f "${f}" ] || continue
        exec_line="$(sed -n "s/^Exec=//p" "${f}" | head -n 1)"
        case "${exec_line}" in
            *xfce4-terminal*)
                case "${exec_line}" in
                    *--disable-server*) ;;
                    *) echo "${f}: ${exec_line}" ;;
                esac
                ;;
        esac
    done
' 2>&1)"
if [ -z "${bad_execs}" ]; then
    pass "all xfce4-terminal EESSI desktop launchers pass --disable-server"
else
    fail "all xfce4-terminal EESSI desktop launchers pass --disable-server (${bad_execs})"
fi

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "neuroimaging-env smoke: all checks passed"
else
    echo "neuroimaging-env smoke: ${FAILED} check(s) failed; container log at /tmp/${NAME}.log"
fi
exit "${FAILED}"
