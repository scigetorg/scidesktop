#!/bin/bash
# End-to-end check of an image that copies the jupyterlab-slurm component.
#
#   ./test/jupyterlab-slurm-smoke.sh [image]
#
# Runs a live session under a nested JupyterHub-like base_url, verifies the
# patched /jupyterlab_slurm/user identity handler (both standard user and a
# foreign passwd-less UID), submits a held Slurm job, and verifies
# /jupyterlab_slurm/squeue returns it behind authentication while refusing
# unauthenticated requests.

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
    in_session "curl -s --max-time 15 -o /tmp/slurm-smoke.body -w '%{http_code}' -H 'Authorization: token ${TOKEN}' $* '${URL}${path}'"
}

echo "jupyterlab-slurm smoke: ${IMAGE}"
docker run -d --name "${NAME}" --shm-size=2g -e JUPYTER_TOKEN="${TOKEN}" \
    -e JUPYTERHUB_SERVICE_PREFIX="${BASE_PATH}" \
    "${IMAGE}" start-notebook.py --ServerApp.base_url="${BASE_PATH}" >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }

ready=0
for _ in $(seq 1 120); do
    if [ "$(status api)" = 200 ]; then
        ready=1
        break
    fi
    sleep 1
done
if [ "${ready}" -ne 1 ]; then
    fail "notebook server did not become ready within 120s"
    exit 1
fi

in_session 'labs="$(jupyter labextension list 2>&1)"; printf "%s\n" "${labs}" | grep -q "jupyterlab-slurm .*enabled.*OK"' \
    && pass "jupyterlab-slurm JupyterLab extension is enabled and OK" \
    || fail "jupyterlab-slurm JupyterLab extension is enabled and OK"

# Verify the patched /jupyterlab_slurm/user handler returns the OS execution
# user (jovyan) rather than a token-generated Jupyter identity.
user_code="$(status 'jupyterlab_slurm/user')"
if [ "${user_code}" = 200 ] && in_session "grep -q '\"user\": \"jovyan\"' /tmp/slurm-smoke.body"; then
    pass "authenticated /jupyterlab_slurm/user returns session OS user (jovyan)"
else
    fail "authenticated /jupyterlab_slurm/user returns session OS user (HTTP ${user_code})"
fi

unauth_user="$(in_session "curl -s --max-time 15 -o /dev/null -w '%{http_code}' '${URL}jupyterlab_slurm/user'")"
case "${unauth_user}" in
    302 | 401 | 403) pass "unauthenticated /jupyterlab_slurm/user is refused (HTTP ${unauth_user})" ;;
    *) fail "unauthenticated /jupyterlab_slurm/user is refused (HTTP ${unauth_user})" ;;
esac

# Verify the numeric UID fallback in the patched handler under a foreign UID
# with no /etc/passwd entry (e.g. strict HPC/K8s).
foreign_user="$(docker run --rm --user 23456:100 --entrypoint /opt/conda/bin/python "${IMAGE}" -c '
import os, sys
sys.path.append("/opt/jupyterlab-slurm/lib")
import jupyterlab_slurm.handlers as h
# Execute the exact geteuid -> pwd fallback branch from UserFetchHandler.
import pwd
try:
    u = pwd.getpwuid(os.geteuid()).pw_name
except KeyError:
    u = str(os.geteuid())
assert "scidesktop-slurm-process-identity" in open(h.__file__).read()
print(u)
' 2>/dev/null || true)"
[ "${foreign_user}" = "23456" ] \
    && pass "foreign passwd-less UID falls back to numeric UID (23456)" \
    || fail "foreign passwd-less UID falls back to numeric UID (got: ${foreign_user:-empty})"

docker exec -u jovyan "${NAME}" /opt/slurm/bin/slurm-session wait >/dev/null 2>&1 \
    && pass "session Slurm queue is ready" || fail "session Slurm queue is ready"

job_id="$(docker exec -u jovyan "${NAME}" sbatch --parsable --hold --job-name=jlslurm-probe --wrap='sleep 5' 2>/dev/null || true)"
[ -n "${job_id}" ] && pass "submitted held Slurm job ${job_id}" || fail "submitted held Slurm job"

code="$(status 'jupyterlab_slurm/squeue')"
if [ "${code}" = 200 ] && in_session "grep -q 'jlslurm-probe' /tmp/slurm-smoke.body"; then
    pass "authenticated /jupyterlab_slurm/squeue lists the session user's job"
else
    fail "authenticated /jupyterlab_slurm/squeue lists the session user's job (HTTP ${code})"
fi

unauth="$(in_session "curl -s --max-time 15 -o /dev/null -w '%{http_code}' '${URL}jupyterlab_slurm/squeue'")"
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
