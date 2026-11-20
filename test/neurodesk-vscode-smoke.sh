#!/bin/bash
# End-to-end check of an image that copies the neurodesk-vscode component.
#
#   ./test/neurodesk-vscode-smoke.sh [image]
#
# A session on a fresh home: the extensions are there for it without a
# download and without a copy in the home, and the VS Code tile starts
# code-server on the folder that holds them.

set -uo pipefail

IMAGE="${1:-neurodesktop}"
NAME="neurodesk-vscode-smoke-$$"
BASE_PATH="/user/vscode-smoke/"
TOKEN="vscode-smoke"
CHECK="$(dirname "$0")/vscode-extensions-check.py"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() { docker rm -f "${NAME}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

in_session() { docker exec -u jovyan "${NAME}" bash -c "$1" 2>/dev/null; }

echo "neurodesk-vscode smoke: ${IMAGE}"
# No network: an extension that had to be downloaded would be missing.
docker run -d --name "${NAME}" --network none -e JUPYTER_TOKEN="${TOKEN}" \
    -e JUPYTERHUB_SERVICE_PREFIX="${BASE_PATH}" \
    "${IMAGE}" start-notebook.py --ServerApp.base_url="${BASE_PATH}" >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }
for _ in $(seq 1 120); do
    in_session "curl -fsS -o /dev/null http://127.0.0.1:8888${BASE_PATH}api" && break
    sleep 1
done

docker exec -i -u jovyan "${NAME}" /opt/conda/bin/python - neurodesk-vscode <"${CHECK}" || fail "extension checks"

# The tile's code-server reads that folder, and the home holds no extension.
code="$(in_session "curl -s -o /dev/null -L --max-time 90 -w '%{http_code}' -H 'Authorization: token ${TOKEN}' 'http://127.0.0.1:8888${BASE_PATH}vscode/'")"
[ "${code}" = 200 ] && pass "the VS Code tile opens the editor" || fail "the VS Code tile opens the editor (HTTP ${code})"
in_session 'pgrep -u jovyan -af "^/opt/code-server/lib/node /opt/code-server" >/tmp/code-server.command; grep -q -- "--builtin-extensions-dir /usr/local/share/code-server/extensions" /tmp/code-server.command' \
    && pass "code-server runs on the system extensions folder" \
    || fail "code-server runs on the system extensions folder"
in_session '[ -z "$(ls "${HOME}/.local/share/code-server/extensions" 2>/dev/null | grep -v "^extensions.json$")" ]' \
    && pass "no extension is copied into the home" || fail "no extension is copied into the home"

echo
echo "  NOT TESTED: VS CODE LISTING AND STARTING THE EXTENSIONS IN A BROWSER."
echo "  code-server lists only a user's own extensions on the command line"
echo "  (--list-extensions), not those of its system folder, and an extension"
echo "  runs only when a browser connects. The files code-server reads were"
echo "  checked above."
echo
if [ "${FAILED}" -eq 0 ]; then
    echo "neurodesk-vscode smoke: all checks passed"
else
    echo "neurodesk-vscode smoke: ${FAILED} check(s) failed"
fi
exit "${FAILED}"
