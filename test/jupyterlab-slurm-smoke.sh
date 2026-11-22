#!/bin/bash
# End-to-end check of an image that copies the jupyterlab-slurm component.
#
#   ./test/jupyterlab-slurm-smoke.sh [image]
#
# Runs a live session under a nested JupyterHub-like base_url, waits for the
# session's Slurm queue, submits a held job, and verifies jupyterlab-slurm's
# server extension returns it behind authentication and refuses unauthenticated
# requests.

set -uo pipefail

IMAGE="${1:-scidesktop}"
NAME="jupyterlab-slurm-smoke-$$"
BASE_PATH="/user/slurm-smoke/"
TOKEN="slurm-smoke"
URL="http://127.0.0.1:8888${BASE_PATH}"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() {
    docker logs "${NAME}" >"/tmp/${NAME}.log" 2>&1 || true
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

in_session() { docker exec "${NAME}" bash -c "$1" 2>/dev/null; }
status() {
    local path="$1"; shift
    in_session "curl -s -o /tmp/slurm-smoke.body -w '%{http_code}' -H 'Authorization: token ${TOKEN}' $* '${URL}${path}'"
}

echo "jupyterlab-slurm smoke: ${IMAGE}"
docker run -d --name "${NAME}" --shm-size=2g -e JUPYTER_TOKEN="${TOKEN}" \
    -e JUPYTERHUB_SERVICE_PREFIX="${BASE_PATH}" \
    "${IMAGE}" start-notebook.py --ServerApp.base_url="${BASE_PATH}" >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }

for _ in $(seq 1 120); do
    [ "$(status api)" = 200 ] && break
    sleep 1
done

in_session 'jupyter labextension list 2>&1 | grep -q "jupyterlab-slurm .*enabled.*OK"' \
    && pass "jupyterlab-slurm JupyterLab extension is enabled and OK" \
    || fail "jupyterlab-slurm JupyterLab extension is enabled and OK"

docker exec -u jovyan "${NAME}" /opt/slurm/bin/slurm-session wait >/dev/null 2>&1 \
    && pass "session Slurm queue is ready" || fail "session Slurm queue is ready"

job_id="$(docker exec -u jovyan "${NAME}" sbatch --parsable --hold --job-name=jlslurm-probe --wrap='sleep 5' 2>/dev/null || true)"
[ -n "${job_id}" ] && pass "submitted held Slurm job ${job_id}" || fail "submitted held Slurm job"

code="$(status 'jupyterlab_slurm/squeue?userOnly=true')"
if [ "${code}" = 200 ] && in_session "grep -q 'jlslurm-probe' /tmp/slurm-smoke.body"; then
    pass "authenticated /jupyterlab_slurm/squeue?userOnly=true lists the session user's job"
else
    fail "authenticated /jupyterlab_slurm/squeue?userOnly=true lists the session user's job (HTTP ${code})"
fi

unauth="$(in_session "curl -s -o /dev/null -w '%{http_code}' '${URL}jupyterlab_slurm/squeue?userOnly=true'")"
case "${unauth}" in
    302 | 401 | 403) pass "unauthenticated /jupyterlab_slurm/squeue is refused (HTTP ${unauth})" ;;
    *) fail "unauthenticated /jupyterlab_slurm/squeue is refused (HTTP ${unauth})" ;;
esac

if [ -n "${job_id}" ]; then
    docker exec -u jovyan "${NAME}" scancel "${job_id}" >/dev/null 2>&1 || true
fi

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "jupyterlab-slurm smoke: all checks passed"
else
    echo "jupyterlab-slurm smoke: ${FAILED} check(s) failed; container log at /tmp/${NAME}.log"
fi
exit "${FAILED}"
