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

[ "$(status server-proxy/servers-info)" = 200 ] && in_session "grep -q '\"name\": \"vscode\"' /tmp/code-server-smoke.body" \
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
# code-server itself listens on no TCP port (checked by socket inode against
# code-server's own PIDs so unrelated background session services such as
# ai-ready's PostgreSQL/Airflow/MLflow cannot race the check).
code="$(in_session "curl -s -o /dev/null -w '%{http_code}' '${URL}vscode/'")"
case "${code}" in
    302 | 401 | 403) pass "a request without the login is refused (HTTP ${code})" ;;
    *) fail "a request without the login is refused (HTTP ${code})" ;;
esac
cs_probe="$(docker exec "${NAME}" /opt/conda/bin/python -c '
import glob, os
listen_inodes = {}
for path in ("/proc/net/tcp", "/proc/net/tcp6"):
    with open(path) as f:
        for line in f.readlines()[1:]:
            parts = line.split()
            if parts[3] == "0A":
                listen_inodes[parts[9]] = int(parts[1].split(":")[1], 16)
pids = 0
found = []
for pid_dir in glob.glob("/proc/[0-9]*"):
    try:
        cmd = open(os.path.join(pid_dir, "cmdline"), "rb").read()
    except OSError:
        continue
    if b"/opt/code-server" not in cmd:
        continue
    pids += 1
    for fd in glob.glob(os.path.join(pid_dir, "fd", "*")):
        try:
            target = os.readlink(fd)
        except OSError:
            continue
        if target.startswith("socket:[") and target.endswith("]"):
            inode = target[8:-1]
            if inode in listen_inodes:
                found.append(str(listen_inodes[inode]))
print(f"OK {pids} " + ",".join(sorted(set(found))))
' 2>/dev/null || echo "FAIL")"
read -r cs_status cs_pids cs_ports <<<"${cs_probe}"
if [ "${cs_status}" = "OK" ] && [ "${cs_pids:-0}" -ge 1 ] && [ -z "${cs_ports:-}" ]; then
    pass "code-server opens no TCP port (${cs_pids} code-server PID(s) inspected)"
else
    fail "code-server opens no TCP port (probe: ${cs_probe})"
fi

in_session '[ -s "${HOME}/.local/share/code-server/User/settings.json" ]' \
    && pass "a new home gets code-server's settings" || fail "a new home gets code-server's settings"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "code-server smoke: all checks passed"
else
    echo "code-server smoke: ${FAILED} check(s) failed; container log at /tmp/${NAME}.log"
fi
exit "${FAILED}"
