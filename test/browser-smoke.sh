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

args=("http://127.0.0.1:${PORT}" "${TOKEN}")
if docker exec "${NAME}" test -f /opt/scidesktop/manifest.d/code-server.json 2>/dev/null; then
    args+=("--has-vscode")
fi

node_flags=()
if ! node -e 'process.exit(typeof WebSocket === "function" ? 0 : 1)' 2>/dev/null; then
    node_flags+=(--experimental-websocket)
fi

node "${node_flags[@]}" "${HERE}/browser-check.mjs" "${args[@]}"
