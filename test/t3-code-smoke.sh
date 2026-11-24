#!/bin/bash
# End-to-end check of an image that copies the t3-code component.
#
#   ./test/t3-code-smoke.sh [image]
#
# Runs one session on a home volume, under a nested URL as JupyterHub serves
# it. The checks of T3 Code through the notebook server are in
# t3-code-check.py; they run before and after a stop, and what the first run
# created must survive it. Nothing here talks to a model provider.

set -uo pipefail

IMAGE="${1:-microdesktop}"
NAME="t3-code-smoke-$$"
BASE_PATH="/user/t3-code-smoke/"
TOKEN="t3-code-smoke"
CHECK="$(dirname "$0")/t3-code-check.py"
STATE='${HOME}/.t3/userdata'
# Prints the PID of the T3 server the notebook user runs, if there is one.
T3_PID='pgrep -u jovyan -f "^/opt/t3-code/app/t3 serve "'
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() {
    docker logs "${NAME}" >"/tmp/${NAME}.log" 2>&1 || true
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
    docker volume rm "${NAME}-home" >/dev/null 2>&1 || true
}
trap cleanup EXIT

finish() {
    echo
    if [ "${FAILED}" -eq 0 ]; then
        echo "t3-code smoke: all checks passed"
    else
        echo "t3-code smoke: ${FAILED} check(s) failed; container log at /tmp/${NAME}.log"
    fi
    exit "${FAILED}"
}

in_session() { docker exec "${NAME}" bash -c "$1" 2>/dev/null; }

# Inside the container, as a browser behind the Hub would reach it: Jupyter's
# Python has the websocket client.
session_checks() {
    for _ in $(seq 1 120); do
        in_session "curl -fsS -o /dev/null http://127.0.0.1:8888${BASE_PATH}api" && break
        sleep 1
    done
    docker exec -i "${NAME}" /opt/conda/bin/python - \
        "http://127.0.0.1:8888${BASE_PATH}" "${TOKEN}" <"${CHECK}" \
        || { fail "session checks ($1)"; finish; }
}

echo "t3-code smoke: ${IMAGE}"
docker volume create "${NAME}-home" >/dev/null
docker run -d --name "${NAME}" --shm-size=2g -v "${NAME}-home:/home/jovyan" \
    -e JUPYTER_TOKEN="${TOKEN}" -e JUPYTERHUB_SERVICE_PREFIX="${BASE_PATH}" \
    "${IMAGE}" start-notebook.py --ServerApp.base_url="${BASE_PATH}" >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }

# T3 Code starts when it is first opened, not with the session.
for _ in $(seq 1 120); do
    in_session "curl -fsS -o /dev/null http://127.0.0.1:8888${BASE_PATH}api" && break
    sleep 1
done
in_session "${T3_PID}" >/dev/null && fail "T3 Code waits for its first request" \
    || pass "T3 Code waits for its first request"

session_checks first

[ -n "$(in_session "${T3_PID}")" ] && pass "T3 Code runs as the notebook user" || fail "T3 Code runs as the notebook user"
external=$(docker exec "${NAME}" python3 -c "
ports = set()
for f in ('/proc/net/tcp', '/proc/net/tcp6'):
    for line in open(f).readlines()[1:]:
        p = line.split()
        addr, port = p[1].split(':')
        if p[3] == '0A' and addr not in ('0100007F', '00000000000000000000000001000000'):
            ports.add(int(port, 16))
print(' '.join(str(p) for p in sorted(ports)))" 2>/dev/null)
[ "${external}" = "8888" ] && pass "only 8888 listens externally" \
    || fail "only 8888 listens externally (got: ${external:-none})"
in_session "[ -s ${STATE}/statev2.sqlite ] && [ -s ${STATE}/settings.json ] \
    && [ \"\$(stat -c %a \${HOME}/.t3)\" = 700 ] \
    && [ \"\$(stat -c %a \${HOME}/.t3/jupyter-proxy-session.json)\" = 600 ]" \
    && pass "T3 Code keeps its state in the home, private to the user" \
    || fail "T3 Code keeps its state in the home, private to the user"
if in_session "test -r /opt/scidesktop/manifest.d/coding-agents.json"; then
    in_session 'test -r /etc/scidesktop/t3-code/settings.d/20-coding-agents.json && /opt/conda/bin/python -c "
import json, pathlib
s = json.loads((pathlib.Path.home() / \".t3/userdata/settings.json\").read_text())
pi = s.get(\"providerInstances\", {})
assert pi.get(\"codex\", {}).get(\"config\", {}).get(\"binaryPath\") == \"/opt/coding-agents/bin/codex\", pi
assert pi.get(\"codex\", {}).get(\"config\", {}).get(\"setupMode\") == \"existing\", pi
assert pi.get(\"opencode\", {}).get(\"enabled\") is True, pi
assert pi.get(\"opencode\", {}).get(\"config\", {}).get(\"binaryPath\") == \"/opt/coding-agents/bin/opencode\", pi
"' \
        && pass "T3 Code seeds bundled Codex (existing CLI mode) and OpenCode" \
        || fail "T3 Code seeds bundled Codex (existing CLI mode) and OpenCode"
fi
environment=$(in_session "cat ${STATE}/environment-id")

# A stop ends T3 Code cleanly: it removes its runtime file and closes its
# database. The grace period is the one the AI Ready images need.
docker stop --time=40 "${NAME}" >/dev/null
docker logs "${NAME}" >"/tmp/${NAME}.log" 2>&1
[ "$(docker inspect "${NAME}" --format '{{.State.ExitCode}}')" = 0 ] \
    && pass "the session stops on request" \
    || fail "the session stops on request (exit code $(docker inspect "${NAME}" --format '{{.State.ExitCode}}'))"
if grep -qE 'Pairing URL|pair#token' "/tmp/${NAME}.log"; then
    fail "T3's pairing token stays out of the container log"
else
    pass "T3's pairing token stays out of the container log"
fi
# T3's client puts a WebSocket ticket in the URL, and the proxy logs the URLs
# it connects to: the log names the connection, not the ticket.
if grep -q 'wsTicket=\[redacted\]' "/tmp/${NAME}.log" && ! grep -q 'wsTicket=[^[]' "/tmp/${NAME}.log"; then
    pass "T3's WebSocket tickets stay out of the container log"
else
    fail "T3's WebSocket tickets stay out of the container log"
fi
docker start "${NAME}" >/dev/null
for _ in $(seq 1 120); do
    in_session "curl -fsS -o /dev/null http://127.0.0.1:8888${BASE_PATH}api" && break
    sleep 1
done
in_session "[ ! -e ${STATE}/server-runtime.json ] && [ ! -e ${STATE}/statev2.sqlite-wal ]" \
    && pass "T3 Code shut down cleanly when the container stopped" \
    || fail "T3 Code shut down cleanly when the container stopped"

session_checks again
[ -n "${environment}" ] && [ "$(in_session "cat ${STATE}/environment-id")" = "${environment}" ] \
    && pass "the restarted session is the same T3 environment" \
    || fail "the restarted session is the same T3 environment"
sessions=$(in_session 't3 auth session list --json' | grep -o '"sessionId"' | wc -l)
[ "${sessions}" = 1 ] && pass "the proxy's earlier T3 session was revoked" \
    || fail "the proxy's earlier T3 session was revoked (${sessions} sessions)"

finish
