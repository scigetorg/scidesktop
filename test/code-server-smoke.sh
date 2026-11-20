#!/bin/bash
# End-to-end check of an image that copies the code-server component.
#
#   ./test/code-server-smoke.sh [image]
#
# Runs one session under a nested URL, as JupyterHub serves it, and opens the
# VS Code tile's address the way a browser would, from inside the container.

set -uo pipefail

IMAGE="${1:-neurodesktop}"
NAME="code-server-smoke-$$"
BASE_PATH="/user/code-server-smoke/"
TOKEN="code-server-smoke"
URL="http://127.0.0.1:8888${BASE_PATH}"
RUNNING='pgrep -u jovyan -f "^/opt/code-server/lib/node /opt/code-server"'
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() {
    docker logs "${NAME}" >"/tmp/${NAME}.log" 2>&1 || true
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

in_session() { docker exec "${NAME}" bash -c "$1" 2>/dev/null; }
# status <path> [curl options]: the HTTP status of a request with the login.
status() {
    local path="$1"; shift
    in_session "curl -s -o /tmp/code-server-smoke.body -w '%{http_code}' -H 'Authorization: token ${TOKEN}' $* '${URL}${path}'"
}

echo "code-server smoke: ${IMAGE}"
docker run -d --name "${NAME}" --shm-size=2g -e JUPYTER_TOKEN="${TOKEN}" \
    -e JUPYTERHUB_SERVICE_PREFIX="${BASE_PATH}" \
    "${IMAGE}" start-notebook.py --ServerApp.base_url="${BASE_PATH}" >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }
for _ in $(seq 1 120); do
    [ "$(status api)" = 200 ] && break
    sleep 1
done

in_session "curl -s -H 'Authorization: token ${TOKEN}' '${URL}server-proxy/servers-info'" \
    | grep -q '"name": "vscode"' \
    && pass "the VS Code tile is in the launcher" || fail "the VS Code tile is in the launcher"
[ "$(status server-proxy/icon/vscode)" = 200 ] && in_session "grep -q '<svg' /tmp/code-server-smoke.body" \
    && pass "the tile has its icon" || fail "the tile has its icon"
in_session "${RUNNING}" >/dev/null \
    && fail "code-server does not run before the tile is opened" \
    || pass "code-server does not run before the tile is opened"

# The first request starts code-server; it must answer with the editor, not
# with an error from a server that is still starting.
code="$(status vscode/ -L --max-time 90)"
[ "${code}" = 200 ] && in_session "grep -q vscode-workbench-web-configuration /tmp/code-server-smoke.body" \
    && pass "the first request opens the editor" || fail "the first request opens the editor (HTTP ${code})"
[ "$(status vscode/healthz)" = 200 ] && in_session "grep -q '\"status\"' /tmp/code-server-smoke.body" \
    && pass "code-server answers through the proxy" || fail "code-server answers through the proxy"
in_session "${RUNNING}" >/dev/null \
    && pass "code-server runs as the notebook user" || fail "code-server runs as the notebook user"

# The notebook server's login is the only way in: no login, no editor, and
# code-server listens on no TCP port.
code="$(in_session "curl -s -o /dev/null -w '%{http_code}' '${URL}vscode/'")"
case "${code}" in
    302 | 401 | 403) pass "a request without the login is refused (HTTP ${code})" ;;
    *) fail "a request without the login is refused (HTTP ${code})" ;;
esac
tcp="$(in_session "cat /proc/net/tcp /proc/net/tcp6 | awk 'NR > 1 && \$4 == \"0A\" { print \$2 }' | sed 's/.*://' | sort -u | tr '\n' ' '")"
# 22B8 is 8888, the notebook server.
[ "${tcp}" = "22B8 " ] \
    && pass "only the notebook server listens on TCP" || fail "only the notebook server listens on TCP (ports, hex: ${tcp})"

in_session '[ -s "${HOME}/.local/share/code-server/User/settings.json" ]' \
    && pass "a new home gets code-server's settings" || fail "a new home gets code-server's settings"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "code-server smoke: all checks passed"
else
    echo "code-server smoke: ${FAILED} check(s) failed; container log at /tmp/${NAME}.log"
fi
exit "${FAILED}"
