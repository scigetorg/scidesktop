#!/bin/bash
# End-to-end check that Notebook Intelligence loads cleanly in a built image.
#
#   ./test/notebook-intelligence-smoke.sh [image]
set -uo pipefail

IMAGE="${1:-scidesktop}"
NAME="nbi-smoke-$$"
PORT="${NBI_SMOKE_PORT:-18993}"
TOKEN="nbi-smoke"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() {
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "notebook-intelligence smoke: ${IMAGE}"
docker run -d --name "${NAME}" -p "127.0.0.1:${PORT}:8888" --shm-size=1g \
    -e JUPYTER_TOKEN="${TOKEN}" "${IMAGE}" >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }

for _ in $(seq 1 120); do
    curl -fsS -o /dev/null "http://127.0.0.1:${PORT}/api" 2>/dev/null && break
    sleep 1
done
if ! curl -fsS -o /dev/null "http://127.0.0.1:${PORT}/api" 2>/dev/null; then
    fail "jupyter did not respond"
    exit 1
fi

page="$(curl -fsS -H "Authorization: token ${TOKEN}" "http://127.0.0.1:${PORT}/lab" 2>/dev/null || true)"
if grep -q '"name": "@plmbr/notebook-intelligence"' <<<"${page}"; then
    pass "JupyterLab page loads @plmbr/notebook-intelligence"
else
    fail "JupyterLab page loads @plmbr/notebook-intelligence"
fi

labs="$(docker exec "${NAME}" bash -lc 'jupyter labextension list 2>&1' || true)"
if grep -q '@plmbr/notebook-intelligence .*enabled.*OK' <<<"${labs}"; then
    pass "@plmbr/notebook-intelligence labextension enabled OK"
else
    fail "@plmbr/notebook-intelligence labextension enabled OK"
fi

caps="$(curl -fsS -H "Authorization: token ${TOKEN}" "http://127.0.0.1:${PORT}/notebook-intelligence/capabilities" 2>/dev/null || true)"
if python3 -c 'import json, sys; d = json.loads(sys.argv[1]); assert isinstance(d, dict) and d' "${caps}" 2>/dev/null; then
    pass "/notebook-intelligence/capabilities returns valid JSON"
else
    fail "/notebook-intelligence/capabilities returns valid JSON (got: ${caps:0:120})"
fi

if ! docker exec "${NAME}" test -e /opt/notebook-intelligence/lib/claude_agent_sdk/_bundled 2>/dev/null; then
    pass "vendored claude_agent_sdk/_bundled binary removed"
else
    fail "vendored claude_agent_sdk/_bundled binary still present"
fi

[ "${FAILED}" -eq 0 ]
