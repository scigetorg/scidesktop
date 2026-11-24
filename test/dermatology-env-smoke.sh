#!/bin/bash
# End-to-end check of an image that copies the dermatology-env component.
#
#   ./test/dermatology-env-smoke.sh [image]
#
# Verifies:
#   - `dermatology` kernel is registered and executes dermatology imaging,
#     colorimetry (CIELAB/ITA), DICOM-VL roundtrip, OpenSlide tiled-TIFF read,
#     OME-TIFF/OME-Zarr bioio roundtrip, and 3D surface mesh analysis
#   - Default `python3` kernel remains on /opt/conda
#   - Domain EESSI desktop launcher tile (app-eessi-napari) registers when EESSI is mounted

set -uo pipefail

IMAGE="${1:-dermdesktop}"
NAME="dermatology-env-smoke-$$"
TOKEN="dermatology-smoke"
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

echo "dermatology-env smoke: ${IMAGE}"
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

docker exec -i "${NAME}" /opt/conda/bin/python - "${TOKEN}" <<'PY' && pass "dermatology kernel, WSI/DICOM/colorimetry/3D mesh roundtrips passed" || fail "dermatology kernel, WSI/DICOM/colorimetry/3D mesh roundtrips passed"
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
assert "dermatology" in specs, f"missing dermatology kernel: {list(specs)}"
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

derm_out = run_code("dermatology", """
import math, pathlib, site, sys, tempfile
import numpy as np
import scipy, pandas, matplotlib, seaborn, sklearn, statsmodels, dask, xarray, imageio, tifffile, imagecodecs, zarr, openslide, pydicom, colour, trimesh, ome_zarr, bioio, watermark
from pydicom.dataset import FileDataset, FileMetaDataset
from pydicom.uid import ExplicitVRLittleEndian, VLPhotographicImageStorage, generate_uid
from skimage.filters import gaussian
from ome_zarr.writer import write_image
from bioio import BioImage

assert sys.executable.startswith("/opt/dermatology-env/"), sys.executable
assert site.ENABLE_USER_SITE is False, f"expected user site disabled, got {site.ENABLE_USER_SITE}"
work = pathlib.Path(tempfile.mkdtemp())

# 1. Whole-slide tiled TIFF read via OpenSlide
rgb = np.full((64, 64, 3), [210, 165, 140], dtype=np.uint8)
rgb[16:48, 16:48] = [95, 55, 45]
wsi_path = work / "biopsy.tif"
tifffile.imwrite(wsi_path, rgb, tile=(32, 32), photometric="rgb")
slide = openslide.OpenSlide(str(wsi_path))
dims = slide.dimensions
assert dims == (64, 64), dims
region = np.asarray(slide.read_region((0, 0), 0, (64, 64)).convert("RGB"))
assert np.array_equal(region, rgb), region.shape
slide.close()

# 2. Colorimetry: sRGB -> CIELAB + Individual Typology Angle (ITA degrees)
xyz = colour.sRGB_to_XYZ(rgb[0, 0] / 255.0)
L, a, b = colour.XYZ_to_Lab(xyz)
ita = math.degrees(math.atan2(L - 50.0, b))
assert -90.0 < ita < 90.0, ita

# 3. DICOM-VL dermoscopy roundtrip via pydicom
fm = FileMetaDataset()
fm.MediaStorageSOPClassUID = VLPhotographicImageStorage
fm.MediaStorageSOPInstanceUID = generate_uid()
fm.TransferSyntaxUID = ExplicitVRLittleEndian
ds = FileDataset(str(work / "derm.dcm"), {}, file_meta=fm, preamble=b"\\0" * 128)
ds.SOPClassUID = fm.MediaStorageSOPClassUID
ds.SOPInstanceUID = fm.MediaStorageSOPInstanceUID
ds.Modality = "XC"
ds.PhotometricInterpretation = "RGB"
ds.SamplesPerPixel = 3
ds.PlanarConfiguration = 0
ds.Rows, ds.Columns = 64, 64
ds.BitsAllocated = 8
ds.BitsStored = 8
ds.HighBit = 7
ds.PixelRepresentation = 0
ds.PixelData = rgb.tobytes()
dcm_path = work / "derm.dcm"
ds.save_as(dcm_path, enforce_file_format=True)
reloaded = pydicom.dcmread(dcm_path)
assert reloaded.Modality == "XC" and np.array_equal(reloaded.pixel_array, rgb)

# 4. OME-TIFF & OME-Zarr bioio roundtrip
vol = np.zeros((4, 16, 16), dtype=np.uint16)
vol[1:3, 4:12, 4:12] = 1000
filt = gaussian(vol.astype(np.float32), sigma=1.0)
assert filt.shape == vol.shape and float(filt.max()) > 0.0
tif_path = work / "stack.ome.tif"
tifffile.imwrite(tif_path, vol, ome=True, metadata={"axes": "ZYX"})
img = BioImage(tif_path)
assert np.array_equal(img.get_image_data("ZYX"), vol)
zarr_path = work / "sample.ome.zarr"
root = zarr.open_group(str(zarr_path), mode="w")
write_image(image=vol, group=root, axes="zyx")
zimg = BioImage(zarr_path)
assert np.array_equal(zimg.get_image_data("ZYX"), vol)

# 5. 3D total-body photography surface mesh check via trimesh
mesh = trimesh.creation.icosphere(subdivisions=2, radius=10.0)
assert mesh.is_watertight and mesh.area > 0.0

print("DERM_OK", dims, round(ita, 1), round(float(mesh.area), 1))
""")
assert "DERM_OK" in derm_out, derm_out

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
    echo "dermatology-env smoke: all checks passed"
else
    echo "dermatology-env smoke: ${FAILED} check(s) failed; container log at /tmp/${NAME}.log"
fi
exit "${FAILED}"
