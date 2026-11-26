#!/bin/bash
# End-to-end check of an image that copies the ai-ready component.
#
#   ./test/ai-ready-smoke.sh [image]
#
# Runs one session on a home volume, at the smallest size the workshop is
# offered at (2 CPUs, 4 GB), under a nested URL as JupyterHub serves it.
# The checks themselves are in ai-ready-check.py. They run before and after a
# restart: what the first run created must survive it.

set -uo pipefail

IMAGE="${1:-datadesktop}"
NAME="ai-ready-smoke-$$"
PORT="${SMOKE_AI_READY_PORT:-18888}"
BASE_PATH="/user/ai-ready-smoke/"
# The origin the session is reached at. Not a loopback name, as on a hub:
# ai-ready-check.py resolves it to this machine.
PUBLIC="http://ai-ready.test:${PORT}"
TOKEN="ai-ready-smoke"
CHECK="$(dirname "$0")/ai-ready-check.py"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

# Whether the container's log has a line matching $1. The log goes to a file
# first: under pipefail, `docker logs | grep -q` fails when grep finds its
# line and exits before docker has written the rest.
logged() {
    docker logs "${NAME}" >"/tmp/${NAME}.log" 2>&1
    grep -qE "$1" "/tmp/${NAME}.log"
}

cleanup() {
    docker logs "${NAME}" >"/tmp/${NAME}.log" 2>&1 || true
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
    docker volume rm "${NAME}-home" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Stops at the first failed group: later ones would only repeat it.
finish() {
    echo
    if [ "${FAILED}" -eq 0 ]; then
        echo "ai-ready smoke: all checks passed"
    else
        echo "ai-ready smoke: ${FAILED} check(s) failed; container log at /tmp/${NAME}.log"
        docker exec "${NAME}" bash -c \
            'find ~/.ai-ready/airflow/logs -path "*task_id*" -type f -exec tail -n 20 {} \;' 2>/dev/null \
            | tail -n 60 | sed 's/^/        /'
    fi
    exit "${FAILED}"
}

session_checks() {
    python3 "${CHECK}" "$1" "${PUBLIC}${BASE_PATH}" "${TOKEN}" \
        || { fail "session checks ($1)"; finish; }
    # Inside the container: Jupyter's Python has the websocket client.
    docker exec -i "${NAME}" /opt/conda/bin/python - kernel \
        "http://127.0.0.1:8888${BASE_PATH}" "${TOKEN}" <"${CHECK}" \
        || { fail "kernel check ($1)"; finish; }
}

echo "ai-ready smoke: ${IMAGE}"
docker volume create "${NAME}-home" >/dev/null
docker run -d --name "${NAME}" --memory=4g --cpus=2 --shm-size=2g \
    -p "127.0.0.1:${PORT}:8888" -v "${NAME}-home:/home/jovyan" \
    -e JUPYTER_TOKEN="${TOKEN}" -e JUPYTERHUB_SERVICE_PREFIX="${BASE_PATH}" \
    -e AI_READY_PUBLIC_ORIGIN="${PUBLIC}" \
    "${IMAGE}" start-notebook.py --ServerApp.base_url="${BASE_PATH}" >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }

session_checks first

# Airflow and MLflow answer only through the notebook server.
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
docker exec "${NAME}" bash -c '[ "$(stat -c %a ~/.ai-ready/credentials.json)" = 600 ]' \
    && pass "generated credentials are private to the user" \
    || fail "generated credentials are private to the user"

# A stop gives the services time to finish: PostgreSQL must not need crash
# recovery afterwards.
docker restart --time=40 "${NAME}" >/dev/null
session_checks again
if logged "database system was (interrupted|not properly shut down)"; then
    fail "PostgreSQL shut down cleanly when the container stopped"
else
    pass "PostgreSQL shut down cleanly when the container stopped"
fi

# The notebook server exits on its own (its shutdown API): nothing signals the
# services but the server's exit handler, which must still stop them in order.
since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
python3 "${CHECK}" shutdown "${PUBLIC}${BASE_PATH}" "${TOKEN}"
ended="$(timeout 60 docker wait "${NAME}" 2>/dev/null)"
docker logs --since "${since}" "${NAME}" >"/tmp/${NAME}.shutdown.log" 2>&1
if [ -n "${ended}" ] && grep -q 'database system is shut down' "/tmp/${NAME}.shutdown.log"; then
    pass "PostgreSQL shut down cleanly when the notebook server exited on its own"
else
    fail "PostgreSQL shut down cleanly when the notebook server exited on its own"
    tail -n 8 "/tmp/${NAME}.shutdown.log" | sed 's/^/        /'
fi
rm -f "/tmp/${NAME}.shutdown.log"
docker start "${NAME}" >/dev/null
python3 "${CHECK}" recovered "${PUBLIC}${BASE_PATH}" "${TOKEN}" \
    && pass "services return after the notebook server's own shutdown" \
    || { fail "services return after the notebook server's own shutdown"; finish; }
if logged "database system was (interrupted|not properly shut down)"; then
    fail "PostgreSQL needed no recovery after the notebook server's own shutdown"
else
    pass "PostgreSQL needed no recovery after the notebook server's own shutdown"
fi

# A killed container leaves PostgreSQL's lock file behind; the next start
# must not mistake it for a running server.
docker kill "${NAME}" >/dev/null && docker start "${NAME}" >/dev/null
python3 "${CHECK}" recovered "${PUBLIC}${BASE_PATH}" "${TOKEN}" \
    && pass "services return after the container was killed" \
    || { fail "services return after the container was killed"; finish; }

# A service that dies takes the session with it, so the failure is seen and
# a restart brings everything back.
docker exec "${NAME}" pkill -f '/opt/ai-ready/env/bin/mlflow server'
if [ "$(timeout 90 docker wait "${NAME}" 2>/dev/null)" != "" ] \
    && logged '\[ai-ready\] FAILED: MLflow exited'; then
    pass "the session ends when a service dies"
else
    fail "the session ends when a service dies"
    docker inspect "${NAME}" --format '        container: {{.State.Status}}, exit code {{.State.ExitCode}}, OOM killed {{.State.OOMKilled}}'
    grep -F '[ai-ready]' "/tmp/${NAME}.log" | tail -n 8 | sed 's/^/        /'
fi

finish
