#!/bin/bash
# End-to-end check of an image that copies the t3-connect component.
#
#   ./test/t3-connect-smoke.sh [image]
#
# Runs one session under a nested URL, as JupyterHub serves it. T3 Connect
# must be off, behind the login, and silent in the container log. Nothing
# here signs in to T3 or contacts its services.

set -uo pipefail

IMAGE="${1:-microdesktop}"
NAME="t3-connect-smoke-$$"
BASE_PATH="/user/t3-connect-smoke/"
TOKEN="t3-connect-smoke"
URL="http://127.0.0.1:8888${BASE_PATH}"
CHECK="$(dirname "$0")/t3-connect-check.py"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() {
    rm -f "/tmp/${NAME}.log" "/tmp/${NAME}.page"
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

in_session() { docker exec -u jovyan "${NAME}" bash -c "$1" 2>/dev/null; }

echo "t3-connect smoke: ${IMAGE}"
docker run -d --name "${NAME}" --shm-size=2g -e JUPYTER_TOKEN="${TOKEN}" \
    -e JUPYTERHUB_SERVICE_PREFIX="${BASE_PATH}" \
    "${IMAGE}" start-notebook.py --ServerApp.base_url="${BASE_PATH}" >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }
for _ in $(seq 1 120); do
    in_session "curl -fsS -o /dev/null ${URL}api" && break
    sleep 1
done

docker exec -i "${NAME}" /opt/conda/bin/python - "${URL}" "${TOKEN}" <"${CHECK}" || fail "page and API checks"
in_session 'pgrep -x cloudflared >/dev/null || pgrep -f "^/opt/t3-code/app/t3 serve " >/dev/null' \
    && fail "looking at T3 Connect starts nothing" || pass "looking at T3 Connect starts nothing"

# T3 Code, once opened, has the relay client and a button to the page, and
# opens no tunnel: nothing was linked.
for _ in $(seq 1 60); do
    in_session "curl -s -o /tmp/t3.page -H 'Authorization: token ${TOKEN}' '${URL}t3-code/' && grep -q 'id=\"root\"' /tmp/t3.page" && break
    sleep 1
done
docker exec "${NAME}" cat /tmp/t3.page >"/tmp/${NAME}.page" 2>/dev/null
grep -qF "const connect = \"${BASE_PATH}t3-connect/\";" "/tmp/${NAME}.page" \
    && pass "T3 Code's page has a button to this session's T3 Connect page" \
    || fail "T3 Code's page has a button to this session's T3 Connect page"
status="$(docker exec -u jovyan "${NAME}" bash -lc 't3 connect status --json' 2>/dev/null | tr -d ' \n')"
case "${status}" in
    *'"desired":false,"authenticated":false,"linked":false'*'"relayClient":{"status":"available"'*)
        pass "T3 has its relay client, and no link" ;;
    *) fail "T3 has its relay client, and no link (got: ${status:0:200})" ;;
esac
sleep 10
in_session 'pgrep -x cloudflared >/dev/null' \
    && fail "T3 Code opens no tunnel while Connect is off" || pass "T3 Code opens no tunnel while Connect is off"
external=$(docker exec "${NAME}" python3 -c "
ports = set()
for f in ('/proc/net/tcp', '/proc/net/tcp6'):
    for line in open(f).readlines()[1:]:
        p = line.split()
        addr, port = p[1].split(':')
        if p[3] == '0A' and addr not in ('0100007F', '00000000000000000000000001000000'):
            ports.add(int(port, 16))
print(' '.join(str(p) for p in sorted(ports)))" 2>/dev/null)
[ "${external}" = "8888" ] && pass "only 8888 listens beyond loopback" \
    || fail "only 8888 listens beyond loopback (got: ${external:-none})"

# Neither T3's pairing token nor a device code is in the container log.
docker logs "${NAME}" >"/tmp/${NAME}.log" 2>&1
if grep -qE 'Pairing URL|pair#token|Confirm this code|[A-Z0-9]{4}-[A-Z0-9]{4}\b.*approv' "/tmp/${NAME}.log"; then
    fail "no pairing token or device code is in the container log"
else
    pass "no pairing token or device code is in the container log"
fi

echo
echo "  NOT TESTED: LINKING WITH A T3 ACCOUNT AND THE TUNNEL TO T3'S RELAY. THAT NEEDS"
echo "  A T3 ACCOUNT AND A PERSON TO APPROVE A CODE. The component's test drives the"
echo "  device authorization with a stand-in for the t3 command."
echo
if [ "${FAILED}" -eq 0 ]; then
    echo "t3-connect smoke: all checks passed"
else
    echo "t3-connect smoke: ${FAILED} check(s) failed"
fi
exit "${FAILED}"
