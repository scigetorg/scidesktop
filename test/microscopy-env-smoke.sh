#!/bin/bash
# End-to-end check of an image that copies the microscopy-env component.
#
#   ./test/microscopy-env-smoke.sh [image]
#
# Verifies:
#   - `microscopy` kernel is registered and executes bioimaging imports plus
#     real OME-TIFF and OME-Zarr write/read roundtrips via tifffile, zarr,
#     ome-zarr, scikit-image, and bioio
#   - Default `python3` kernel remains on /opt/conda
#   - Domain EESSI desktop launcher tile (app-eessi-napari) registers when EESSI is mounted

set -uo pipefail

IMAGE="${1:-microdesktop}"
NAME="microscopy-env-smoke-$$"
TOKEN="microscopy-smoke"
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

echo "microscopy-env smoke: ${IMAGE}"
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

docker exec -i "${NAME}" /opt/conda/bin/python - "${TOKEN}" <<'PY' && pass "microscopy kernel and OME-TIFF/OME-Zarr bioio roundtrip passed" || fail "microscopy kernel and OME-TIFF/OME-Zarr bioio roundtrip passed"
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
assert "microscopy" in specs, f"missing microscopy kernel: {list(specs)}"
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

micro_out = run_code("microscopy", """
import pathlib, site, sys, tempfile
import numpy as np
import scipy, pandas, matplotlib, seaborn, sklearn, dask, xarray, imageio, tifffile, imagecodecs, zarr, ome_zarr, bioio, watermark
from skimage.filters import gaussian
from ome_zarr.writer import write_image
from bioio import BioImage

assert sys.executable.startswith("/opt/microscopy-env/"), sys.executable
assert site.ENABLE_USER_SITE is False, f"expected user site disabled, got {site.ENABLE_USER_SITE}"
work = pathlib.Path(tempfile.mkdtemp())

# Synthetic 3D microscopy stack: Gaussian filter + OME-TIFF/BioImage roundtrip
vol = np.zeros((4, 16, 16), dtype=np.uint16)
vol[1:3, 4:12, 4:12] = 1000
filt = gaussian(vol.astype(np.float32), sigma=1.0)
assert filt.shape == vol.shape and float(filt.max()) > 0.0, (filt.shape, float(filt.max()))
tif_path = work / "stack.ome.tif"
tifffile.imwrite(tif_path, vol, ome=True, metadata={"axes": "ZYX"})
img = BioImage(tif_path)
assert img.dims.order == "TCZYX" and img.data.shape[-3:] == (4, 16, 16), img.data.shape
tif_zyx = img.get_image_data("ZYX")
assert tif_zyx.dtype == vol.dtype and np.array_equal(tif_zyx, vol), (tif_zyx.dtype, tif_zyx.shape)

# OME-Zarr write + BioImage/zarr read roundtrip
zarr_path = work / "sample.ome.zarr"
root = zarr.open_group(str(zarr_path), mode="w")
write_image(image=vol, group=root, axes="zyx")
zimg = BioImage(zarr_path)
assert zimg.data.shape[-3:] == (4, 16, 16), zimg.data.shape
zarr_zyx = zimg.get_image_data("ZYX")
assert zarr_zyx.dtype == vol.dtype and np.array_equal(zarr_zyx, vol), (zarr_zyx.dtype, zarr_zyx.shape)
print("MICRO_OK", img.data.shape, zimg.data.shape, round(float(filt.max()), 1))
""")
assert "MICRO_OK" in micro_out, micro_out

base_out = run_code("python3", "import sys; print(sys.executable)")
assert base_out.startswith("/opt/conda/"), base_out
PY

servers="$(docker exec "${NAME}" curl -fsS -H "Authorization: token ${TOKEN}" \
    "http://127.0.0.1:8888/server-proxy/servers-info" 2>/dev/null || true)"
if grep -q '"app-eessi-napari"' <<<"${servers}"; then
    pass "JupyterLab launcher registers app-eessi-napari when EESSI is mounted"
else
    fail "JupyterLab launcher registers app-eessi-napari when EESSI is mounted"
fi

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "microscopy-env smoke: all checks passed"
else
    echo "microscopy-env smoke: ${FAILED} check(s) failed; container log at /tmp/${NAME}.log"
fi
exit "${FAILED}"
