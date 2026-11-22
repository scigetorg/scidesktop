#!/bin/bash
# End-to-end check of notebook kernel execution (WebSocket, MODULEPATH/Lmod,
# error recovery, Contents CRUD, nbconvert) and live sciget install + execution
# (+ scigethelpers cite when scigethelpers-cli is in the image).
#
#   ./test/notebook-and-sciget-smoke.sh [image]

set -uo pipefail

IMAGE="${1:-scidesktop}"
NAME="notebook-sciget-smoke-$$"
TOKEN="notebook-sciget-smoke"
HERE="$(cd "$(dirname "$0")" && pwd)"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() {
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

as_user() { docker exec -u jovyan -w /home/jovyan "${NAME}" bash -lc "$1" 2>&1; }

echo "notebook & sciget smoke: ${IMAGE}"
fuse_args=()
[ -c /dev/fuse ] && fuse_args=(--device /dev/fuse)
docker run -d --name "${NAME}" --shm-size=1g \
    "${fuse_args[@]}" \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
    -e JUPYTER_TOKEN="${TOKEN}" "${IMAGE}" >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }

for _ in $(seq 1 120); do
    docker exec "${NAME}" curl -fsS -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null && break
    sleep 1
done
if ! docker exec "${NAME}" curl -fsS -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null; then
    fail "jupyter did not become ready"
    exit 1
fi

# 1. Contents CRUD, WebSocket kernel execution, MODULEPATH, error recovery, nbconvert
docker cp "${HERE}/notebook-check.py" "${NAME}:/tmp/notebook-check.py" >/dev/null
if docker exec -u jovyan -w /home/jovyan "${NAME}" /opt/conda/bin/python3 /tmp/notebook-check.py "http://127.0.0.1:8888" "${TOKEN}"; then
    pass "notebook CRUD, kernel WebSocket execution, MODULEPATH and nbconvert passed"
else
    fail "notebook CRUD, kernel WebSocket execution, MODULEPATH and nbconvert failed"
fi

# 2. Live sciget install + module load + container execution (on images whose
#    catalog offers niimath / niimath_arm64 — a small, fast multi-arch tool).
arch="$(docker exec "${NAME}" uname -m)"
if [ "${arch}" = "aarch64" ]; then
    tool="niimath_arm64"
else
    tool="niimath"
fi

# Wait for background catalog refresh.
as_user 'for _ in $(seq 1 60); do [ -n "$(ls -A ~/.cache/sciget/catalogs 2>/dev/null)" ] && exit 0; sleep 1; done; exit 1' >/dev/null || true

# Require a neuroimaging tool when the image's system catalogs include neuroimaging;
# only skip when the image intentionally narrowed away from neuroimaging.
has_neuro=0
docker exec "${NAME}" grep -q '"neuroimaging"' /etc/sciget/catalogs.json 2>/dev/null && has_neuro=1

if [ "${has_neuro}" = "1" ]; then
    spec="$(as_user "sciget find '${tool}'" | awk -F '\t' -v t="${tool}/" 'index($1, t) == 1 { print $1; exit }')"
    if [ -z "${spec}" ]; then
        fail "sciget find ${tool} returned a version from the neuroimaging catalog"
    elif out="$(as_user "sciget install '${spec}'")"; then
        pass "sciget installed ${spec}"
        # Run a real voxel operation (create 4x4x4 NIfTI, add 5 with niimath, verify voxel mean == 5).
        run_out="$(as_user "
            set -e
            /opt/conda/bin/python3 -c '
import gzip, struct
h = bytearray(352)
struct.pack_into(\"<I\", h, 0, 348)
struct.pack_into(\"<8h\", h, 40, 3, 4, 4, 4, 1, 1, 1, 1)
struct.pack_into(\"<hh\", h, 70, 16, 32)
struct.pack_into(\"<8f\", h, 76, 1, 1, 1, 1, 1, 1, 1, 1)
struct.pack_into(\"<f\", h, 108, 352.0)
h[344:348] = b\"n+1\\x00\"
with gzip.open(\"/tmp/niimath_in.nii.gz\", \"wb\") as f:
    f.write(h + bytes(4 * 4 * 4 * 4))
'
            module load '${spec}'
            niimath /tmp/niimath_in.nii.gz -add 5 /tmp/niimath_out.nii.gz
            /opt/conda/bin/python3 -c '
import gzip, struct
data = gzip.open(\"/tmp/niimath_out.nii.gz\", \"rb\").read()
vals = struct.unpack(\"<64f\", data[352:352 + 256])
assert all(abs(v - 5.0) < 1e-4 for v in vals), vals[:8]
print(\"NIIMATH_MATH_OK\")
'")"
        if grep -qx 'NIIMATH_MATH_OK' <<<"${run_out}"; then
            pass "module load ${spec} runs niimath arithmetic inside Apptainer"
        else
            fail "module load ${spec} runs niimath arithmetic inside Apptainer"
            printf '%s\n' "${run_out}" | tail -n 15 | sed 's/^/        /'
        fi
        # When scigethelpers-cli is installed, verify real module load recorded
        # by Lmod produces a real CITATIONS.md entry from the live catalog.
        if docker exec "${NAME}" test -f /opt/scidesktop/manifest.d/scigethelpers-cli.json 2>/dev/null; then
            cite_out="$(as_user "scigethelpers cite && grep -q '${tool}' ~/CITATIONS.md && echo CITE_OK")"
            if grep -qx 'CITE_OK' <<<"${cite_out}"; then
                pass "scigethelpers cite writes real citation for ${spec}"
            else
                fail "scigethelpers cite writes real citation for ${spec}"
                printf '%s\n' "${cite_out}" | tail -n 10 | sed 's/^/        /'
            fi
        fi
    else
        fail "sciget installed ${spec}"
        printf '%s\n' "${out}" | tail -n 15 | sed 's/^/        /'
    fi
else
    pass "narrowed domain image without neuroimaging catalog; skipped ${tool} install"
fi

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "notebook & sciget smoke: all checks passed"
else
    echo "notebook & sciget smoke: ${FAILED} check(s) failed"
fi
exit "${FAILED}"
