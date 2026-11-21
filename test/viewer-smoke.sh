#!/bin/bash
# End-to-end check of an image that copies a JupyterLab viewer component.
# Called by test/jupyterlab-niivue-smoke.sh and
# test/jupyterlab-freebrowse-smoke.sh.
#
#   ./test/viewer-smoke.sh <image> <component>
#
# Runs one session under a nested URL, as JupyterHub serves it. The checks
# are in viewer-check.py.

set -uo pipefail

IMAGE="${1:?usage: viewer-smoke.sh <image> <component>}"
COMPONENT="${2:?}"
NAME="${COMPONENT}-smoke-$$"
BASE_PATH="/user/viewer-smoke/"
TOKEN="viewer-smoke"
CHECK="$(dirname "$0")/viewer-check.py"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() { docker rm -f "${NAME}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "${COMPONENT} smoke: ${IMAGE}"
docker run -d --name "${NAME}" -e JUPYTER_TOKEN="${TOKEN}" -e JUPYTERHUB_SERVICE_PREFIX="${BASE_PATH}" \
    "${IMAGE}" start-notebook.py --ServerApp.base_url="${BASE_PATH}" >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }
for _ in $(seq 1 120); do
    docker exec "${NAME}" curl -fsS -o /dev/null "http://127.0.0.1:8888${BASE_PATH}api" 2>/dev/null && break
    sleep 1
done

docker exec -u jovyan "${NAME}" bash -lc 'jupyter labextension list' >"/tmp/${NAME}.labextensions" 2>&1
grep -A 40 '^/usr/local/share/jupyter/labextensions' "/tmp/${NAME}.labextensions" | grep -q 'enabled.*OK' \
    && pass "JupyterLab lists the viewer's extension as enabled" \
    || fail "JupyterLab lists the viewer's extension as enabled"
rm -f "/tmp/${NAME}.labextensions"

docker exec -i "${NAME}" /opt/conda/bin/python - "http://127.0.0.1:8888${BASE_PATH}" "${TOKEN}" "${COMPONENT}" \
    <"${CHECK}" || fail "viewer checks"

echo
echo "  NOT TESTED: THE VIEWER DRAWING THE IMAGE. THAT NEEDS A BROWSER WITH WEBGL,"
echo "  WHICH THIS TEST DOES NOT HAVE. What JupyterLab needs to open a file in the"
echo "  viewer was checked above."
echo
if [ "${FAILED}" -eq 0 ]; then
    echo "${COMPONENT} smoke: all checks passed"
else
    echo "${COMPONENT} smoke: ${FAILED} check(s) failed"
fi
exit "${FAILED}"
