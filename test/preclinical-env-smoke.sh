#!/bin/bash
# End-to-end check of an image that copies the preclinical-env component.
#
#   ./test/preclinical-env-smoke.sh [image]
#
# Verifies:
#   - `preclinical` kernel is registered and executes NIfTI (nibabel),
#     SimpleITK resampling, DICOM roundtrip (pydicom), brkraw import, and
#     ipyniivue widget creation
#   - Default `python3` kernel remains on /opt/conda
#   - Domain EESSI desktop launcher tile (app-eessi-napari) registers when EESSI is mounted

set -uo pipefail

IMAGE="${1:-preclinicaldesktop}"
NAME="preclinical-env-smoke-$$"
TOKEN="preclinical-smoke"
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

echo "preclinical-env smoke: ${IMAGE}"
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

docker exec -i "${NAME}" /opt/conda/bin/python - "${TOKEN}" <<'PY' && pass "preclinical kernel, NIfTI/SimpleITK/DICOM/brkraw/ipyniivue checks passed" || fail "preclinical kernel, NIfTI/SimpleITK/DICOM/brkraw/ipyniivue checks passed"
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
assert "preclinical" in specs, f"missing preclinical kernel: {list(specs)}"
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

pc_out = run_code("preclinical", """
import pathlib, site, sys, tempfile
import numpy as np
import scipy, pandas, matplotlib, seaborn, skimage, sklearn, statsmodels, dask, xarray, imageio, tifffile, zarr, pydicom, SimpleITK as sitk, nibabel as nib, nilearn, ipyniivue, brkraw, watermark
from pydicom.dataset import FileDataset, FileMetaDataset
from pydicom.uid import ExplicitVRLittleEndian, MRImageStorage, generate_uid

assert sys.executable.startswith("/opt/preclinical-env/"), sys.executable
assert site.ENABLE_USER_SITE is False, f"expected user site disabled, got {site.ENABLE_USER_SITE}"
work = pathlib.Path(tempfile.mkdtemp())

# 1. NIfTI small-animal isotropic 0.1 mm volume roundtrip via nibabel
vol = np.zeros((16, 16, 16), dtype=np.float32)
vol[4:12, 4:12, 4:12] = 42.0
affine = np.diag([0.1, 0.1, 0.1, 1.0])
nii_path = work / "mouse_t2.nii.gz"
nib.save(nib.Nifti1Image(vol, affine), nii_path)
reloaded_nii = nib.load(nii_path)
assert reloaded_nii.shape == (16, 16, 16) and np.allclose(reloaded_nii.get_fdata(), vol)

# 2. SimpleITK 3D Gaussian smoothing
sitk_img = sitk.GetImageFromArray(vol)
sitk_img.SetSpacing((0.1, 0.1, 0.1))
smoothed = sitk.SmoothingRecursiveGaussian(sitk_img, sigma=0.2)
assert smoothed.GetSize() == (16, 16, 16)

# 3. DICOM MR roundtrip via pydicom
slc = (vol[:, :, 8] * 10).astype(np.uint16)
fm = FileMetaDataset()
fm.MediaStorageSOPClassUID = MRImageStorage
fm.MediaStorageSOPInstanceUID = generate_uid()
fm.TransferSyntaxUID = ExplicitVRLittleEndian
ds = FileDataset(str(work / "mri.dcm"), {}, file_meta=fm, preamble=b"\\0" * 128)
ds.SOPClassUID = fm.MediaStorageSOPClassUID
ds.SOPInstanceUID = fm.MediaStorageSOPInstanceUID
ds.Modality = "MR"
ds.PhotometricInterpretation = "MONOCHROME2"
ds.SamplesPerPixel = 1
ds.Rows, ds.Columns = slc.shape
ds.BitsAllocated = 16
ds.BitsStored = 16
ds.HighBit = 15
ds.PixelRepresentation = 0
ds.PixelData = slc.tobytes()
dcm_path = work / "mri.dcm"
ds.save_as(dcm_path, enforce_file_format=True)
reloaded_dcm = pydicom.dcmread(dcm_path)
assert reloaded_dcm.Modality == "MR" and np.array_equal(reloaded_dcm.pixel_array, slc)

# 4. ipyniivue widget instantiation
nv = ipyniivue.NiiVue()
assert nv is not None

print("PRECLIN_OK", reloaded_nii.shape, sitk.Version_VersionString())
""")
assert "PRECLIN_OK" in pc_out, pc_out

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
    echo "preclinical-env smoke: all checks passed"
else
    echo "preclinical-env smoke: ${FAILED} check(s) failed; container log at /tmp/${NAME}.log"
fi
exit "${FAILED}"
