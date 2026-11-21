#!/bin/bash
# End-to-end check of an image that copies the acp-adapters component.
#
#   ./test/acp-adapters-smoke.sh [image]
#
# In a started session, as the notebook user: each adapter is where Jupyter
# AI looks for it and speaks the protocol with the image's own agent. No
# message goes to a model. The checks are in acp-adapters-check.py.

set -uo pipefail

IMAGE="${1:-microdesktop}"
NAME="acp-adapters-smoke-$$"
CHECK="$(dirname "$0")/acp-adapters-check.py"
FAILED=0

cleanup() { docker rm -f "${NAME}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "acp-adapters smoke: ${IMAGE}"
docker run -d --name "${NAME}" -e JUPYTER_TOKEN=acp-adapters-smoke "${IMAGE}" >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }
for _ in $(seq 1 120); do
    docker exec "${NAME}" curl -fsS -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null && break
    sleep 1
done
# With the environment the notebook server has, which is what Jupyter AI
# starts the adapters with.
docker exec -i -u jovyan "${NAME}" bash -c 'exec env $(tr "\0" "\n" </proc/$(pgrep -u jovyan -f jupyter-lab | head -n 1)/environ | grep "^PATH=") /opt/conda/bin/python -' \
    <"${CHECK}" || FAILED=1

echo
echo "  NOT TESTED: THE CODEX AND CLAUDE PERSONAS ANSWERING IN A CHAT. THAT NEEDS A"
echo "  BROWSER AND A SIGNED-IN AGENT."
echo
if [ "${FAILED}" -eq 0 ]; then
    echo "acp-adapters smoke: all checks passed"
else
    echo "acp-adapters smoke: check(s) failed"
fi
exit "${FAILED}"
