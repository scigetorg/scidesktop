#!/bin/bash
# End-to-end check of jupyterlab-scigethelpers in an assembled image.
#
#   ./test/jupyterlab-scigethelpers-smoke.sh [image]
set -uo pipefail

IMAGE="${1:-scidesktop}"
NAME="jupyterlab-scigethelpers-smoke-$$"
TOKEN="scigethelpers-smoke"
HERE="$(cd "$(dirname "$0")" && pwd)"

cleanup() { docker rm -f "${NAME}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "jupyterlab-scigethelpers smoke: ${IMAGE}"
docker run -d --name "${NAME}" --cpus=2 --memory=2g \
    -e JUPYTER_TOKEN="${TOKEN}" \
    "${IMAGE}" \
    start-notebook.py --ServerApp.base_url=/user/smoke/ >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }

for _ in $(seq 1 120); do
    docker exec "${NAME}" curl -fsS -o /dev/null "http://127.0.0.1:8888/user/smoke/api" 2>/dev/null && break
    sleep 1
done

docker exec -i -u jovyan "${NAME}" /opt/conda/bin/python3 - \
    "http://127.0.0.1:8888/user/smoke/" "${TOKEN}" < "${HERE}/jupyterlab-scigethelpers-check.py"
