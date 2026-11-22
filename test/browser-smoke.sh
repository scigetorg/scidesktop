#!/bin/bash
# Real headless Chrome/Chromium + SwiftShader WebGL2 smoke check:
#   - JupyterLab launcher tiles & WebGL2
#   - NiiVue WebGL2 rendering of a synthetic 3D NIfTI volume
#   - FreeBrowse WebGL canvas
#   - Jupyter AI Chat UI & OpenCode/Codex/Claude personas
#   - T3 Code SPA behind the base-path proxy
#   - VS Code (code-server) workbench when present in the image
#
#   ./test/browser-smoke.sh [image]
#
# Needs Node.js >= 22 (built-in WebSocket) and google-chrome or chromium on the
# host (installed by default on GitHub Actions ubuntu-24.04 runners).

set -uo pipefail

IMAGE="${1:-scidesktop}"
NAME="browser-smoke-$$"
PORT="${BROWSER_SMOKE_PORT:-18997}"
TOKEN="browser-smoke"
HERE="$(cd "$(dirname "$0")" && pwd)"

cleanup() {
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! command -v node >/dev/null 2>&1; then
    echo "browser smoke: node is required on the host" >&2
    exit 1
fi
if [ -z "${BROWSER_BIN:-}" ] && ! command -v google-chrome >/dev/null 2>&1 \
    && ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1; then
    echo "browser smoke: google-chrome or chromium is required on the host" >&2
    exit 1
fi

echo "browser smoke: ${IMAGE}"
docker run -d --name "${NAME}" -p "127.0.0.1:${PORT}:8888" --shm-size=2g \
    -e JUPYTER_TOKEN="${TOKEN}" "${IMAGE}" >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }

for _ in $(seq 1 120); do
    curl -fsS -o /dev/null "http://127.0.0.1:${PORT}/api" 2>/dev/null && break
    sleep 1
done
if ! curl -fsS -o /dev/null "http://127.0.0.1:${PORT}/api" 2>/dev/null; then
    echo "  FAIL  jupyter did not respond"
    exit 1
fi

# Seed a synthetic 32x32x32 float32 NIfTI-1 brain-sphere volume inside the
# user's home so NiiVue and FreeBrowse render real volume slices.
docker exec -i -u jovyan "${NAME}" /opt/conda/bin/python3 - <<'PY' || { echo "  FAIL  could not seed smoke_brain.nii.gz"; exit 1; }
import gzip, struct

nx, ny, nz = 32, 32, 32
header = bytearray(352)
struct.pack_into("<I", header, 0, 348)            # sizeof_hdr
struct.pack_into("<8h", header, 40, 3, nx, ny, nz, 1, 1, 1, 1)  # dim
struct.pack_into("<h", header, 70, 16)            # datatype = DT_FLOAT32
struct.pack_into("<h", header, 72, 32)            # bitpix
struct.pack_into("<8f", header, 76, 1.0, 2.0, 2.0, 2.0, 1.0, 1.0, 1.0, 1.0)  # pixdim
struct.pack_into("<f", header, 108, 352.0)        # vox_offset
struct.pack_into("<f", header, 112, 1.0)          # scl_slope
struct.pack_into("<h", header, 252, 1)            # qform_code
struct.pack_into("<h", header, 254, 1)            # sform_code
struct.pack_into("<4f", header, 280, 2.0, 0.0, 0.0, -32.0)  # srow_x
struct.pack_into("<4f", header, 296, 0.0, 2.0, 0.0, -32.0)  # srow_y
struct.pack_into("<4f", header, 312, 0.0, 0.0, 2.0, -32.0)  # srow_z
header[344:348] = b"n+1\x00"                      # magic

cx, cy, cz, r2 = nx / 2.0, ny / 2.0, nz / 2.0, 10.0 ** 2
voxels = bytearray(nx * ny * nz * 4)
off = 0
for z in range(nz):
    for y in range(ny):
        for x in range(nx):
            d2 = (x - cx) ** 2 + (y - cy) ** 2 + (z - cz) ** 2
            val = 1000.0 * (1.0 - d2 / r2) if d2 < r2 else 0.0
            struct.pack_into("<f", voxels, off, val)
            off += 4

with gzip.open("/home/jovyan/smoke_brain.nii.gz", "wb") as f:
    f.write(header)
    f.write(voxels)
PY

# Seed a 2-slide notebook for RISE presentation rendering check.
docker exec -i -u jovyan "${NAME}" /opt/conda/bin/python3 - <<'PY' || { echo "  FAIL  could not seed smoke_slides.ipynb"; exit 1; }
import json

nb = {
    "cells": [
        {
            "cell_type": "markdown",
            "id": "slide-1",
            "metadata": {"slideshow": {"slide_type": "slide"}},
            "source": ["# SciDesktop RISE Slide 1\n", "\n", "Rendered by Reveal.js."],
        },
        {
            "cell_type": "markdown",
            "id": "slide-2",
            "metadata": {"slideshow": {"slide_type": "slide"}},
            "source": ["# SciDesktop RISE Slide 2\n", "\n", "Second slide body."],
        },
    ],
    "metadata": {
        "kernelspec": {"display_name": "Python 3 (ipykernel)", "language": "python", "name": "python3"},
        "language_info": {"name": "python"},
    },
    "nbformat": 4,
    "nbformat_minor": 5,
}
with open("/home/jovyan/smoke_slides.ipynb", "w") as f:
    json.dump(nb, f)
PY

args=("http://127.0.0.1:${PORT}" "${TOKEN}")
if docker exec "${NAME}" test -f /opt/scidesktop/manifest.d/code-server.json 2>/dev/null; then
    args+=("--has-vscode")
fi
if docker exec "${NAME}" test -f /opt/scidesktop/manifest.d/jupyterlab-niivue.json 2>/dev/null; then
    args+=("--has-niivue")
fi
if docker exec "${NAME}" test -f /opt/scidesktop/manifest.d/jupyterlab-neuroglancer.json 2>/dev/null; then
    # Seed a synthetic 32x32x32 uint8 OME-Zarr v0.4 volume so Neuroglancer
    # renders real 3D microscopy slices from /files/ behind Jupyter's login.
    docker exec -i -u jovyan "${NAME}" /opt/conda/bin/python3 - <<'PY' || { echo "  FAIL  could not seed smoke_micro.ome.zarr"; exit 1; }
import json, pathlib

root = pathlib.Path("/home/jovyan/smoke_micro.ome.zarr")
(root / "0").mkdir(parents=True, exist_ok=True)
(root / ".zgroup").write_text(json.dumps({"zarr_format": 2}))
(root / ".zattrs").write_text(json.dumps({
    "multiscales": [{
        "version": "0.4",
        "name": "smoke_micro",
        "axes": [
            {"name": "z", "type": "space", "unit": "micrometer"},
            {"name": "y", "type": "space", "unit": "micrometer"},
            {"name": "x", "type": "space", "unit": "micrometer"},
        ],
        "datasets": [{
            "path": "0",
            "coordinateTransformations": [{"type": "scale", "scale": [1.0, 1.0, 1.0]}],
        }],
    }],
    "omero": {
        "channels": [{
            "active": True,
            "color": "00FF88",
            "label": "GFP",
            "window": {"start": 0, "end": 255, "min": 0, "max": 255},
        }],
    },
}))
nx, ny, nz = 32, 32, 32
(root / "0" / ".zarray").write_text(json.dumps({
    "zarr_format": 2,
    "shape": [nz, ny, nx],
    "chunks": [nz, ny, nx],
    "dtype": "|u1",
    "compressor": None,
    "fill_value": 0,
    "order": "C",
    "filters": None,
}))
cx, cy, cz, r2 = nx / 2.0, ny / 2.0, nz / 2.0, 12.0 ** 2
buf = bytearray(nx * ny * nz)
off = 0
for z in range(nz):
    for y in range(ny):
        for x in range(nx):
            d2 = (x - cx) ** 2 + (y - cy) ** 2 + (z - cz) ** 2
            buf[off] = int(255.0 * (1.0 - d2 / r2)) if d2 < r2 else 0
            off += 1
(root / "0" / "0.0.0").write_bytes(buf)
PY
    args+=("--has-neuroglancer")
fi
if docker exec "${NAME}" test -f /opt/scidesktop/manifest.d/neuroimaging-env.json 2>/dev/null; then
    # Seed a notebook with two ipyniivue.NiiVue() widgets on the neuroimaging kernel.
    docker exec -i -u jovyan "${NAME}" /opt/conda/bin/python3 - <<'PY' || { echo "  FAIL  could not seed smoke_ipyniivue.ipynb"; exit 1; }
import json

nb = {
    "cells": [
        {
            "cell_type": "code",
            "execution_count": None,
            "id": "nv-1",
            "metadata": {},
            "outputs": [],
            "source": [
                "from ipyniivue import NiiVue\n",
                "nv1 = NiiVue(height=240)\n",
                "nv1\n",
            ],
        },
        {
            "cell_type": "code",
            "execution_count": None,
            "id": "nv-2",
            "metadata": {},
            "outputs": [],
            "source": [
                "nv2 = NiiVue(height=240)\n",
                "nv2\n",
            ],
        },
    ],
    "metadata": {
        "kernelspec": {"display_name": "Neuroimaging (Python 3.13)", "language": "python", "name": "neuroimaging"},
        "language_info": {"name": "python"},
    },
    "nbformat": 4,
    "nbformat_minor": 5,
}
with open("/home/jovyan/smoke_ipyniivue.ipynb", "w") as f:
    json.dump(nb, f)
PY
    args+=("--has-neuroimaging")
fi

node_flags=()
if ! node -e 'process.exit(typeof WebSocket === "function" ? 0 : 1)' 2>/dev/null; then
    node_flags+=(--experimental-websocket)
fi

node "${node_flags[@]}" "${HERE}/browser-check.mjs" "${args[@]}"
