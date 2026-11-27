#!/bin/bash
# Lightweight base-integrity smoke check for domain images whose added
# components do not modify startup hooks, shell profiles, home defaults,
# modulepath, CVMFS, or desktop menus (verified by `contract.py surfaces`).
#
# Full desktop/CVMFS/Hub/Apptainer session checks already ran on the base image
# (whose layers are copied unchanged). This check verifies that the flavour's
# added layers did not break Jupyter server startup, extension loading, loopback
# isolation, manifest integrity, folder permissions, or security hygiene.
#
#   ./test/flavour-smoke.sh <image>

set -uo pipefail

IMAGE="${1:?usage: flavour-smoke.sh <image>}"
NAME="flavour-smoke-$$"
TOKEN="flavour-smoke"
HERE="$(cd "$(dirname "$0")" && pwd)"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() {
    docker logs "${NAME}" >"/tmp/${NAME}.log" 2>&1 || true
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "flavour smoke: ${IMAGE}"
docker run -d --name "${NAME}" --shm-size=1g \
    -e JUPYTER_TOKEN="${TOKEN}" "${IMAGE}" >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }

ready=0
for _ in $(seq 1 120); do
    if docker exec "${NAME}" curl -fsS -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null; then
        ready=1
        break
    fi
    sleep 1
done
if [ "${ready}" -eq 1 ]; then
    pass "jupyter responds"
else
    fail "jupyter responds"; exit 1
fi

page="$(docker exec "${NAME}" curl -s -H "Authorization: token ${TOKEN}" "http://127.0.0.1:8888/lab")"
if grep -q '"name": "jupyterlab-chat-extension"' <<<"${page}" \
    && grep -q '"name": "@jupyter-ai/acp-client"' <<<"${page}" \
    && grep -q '"name": "@jupyter-ai/persona-manager"' <<<"${page}"; then
    pass "JupyterLab's page loads the Jupyter AI chat extensions"
else
    fail "JupyterLab's page loads the Jupyter AI chat extensions"
fi

ext_out="$(docker exec "${NAME}" bash -lc 'jupyter server extension list' 2>&1)"
if [ "$(grep -c -E '(jupyter_ai_acp_client|jupyter_ai_persona_manager|jupyter_ai_router|jupyterlab_chat|jupyter_live_content) .*OK' <<<"${ext_out}")" = 5 ]; then
    pass "the notebook server loads the Jupyter AI extensions"
else
    fail "the notebook server loads the Jupyter AI extensions"
fi

code="$(docker exec "${NAME}" curl -s -o /dev/null -w '%{http_code}' -H "Authorization: token ${TOKEN}" \
    "http://127.0.0.1:8888/api/contents/.bashrc?content=0" 2>/dev/null)"
[ "${code}" = 200 ] && pass "hidden files served (server settings loaded)" \
    || fail "hidden files served (server settings loaded) (got HTTP ${code})"

# Open the desktop route before checking listeners so any service started on
# demand (Selkies, desktop session helpers) is also verified to stay on loopback.
desktop_code="$(docker exec "${NAME}" curl -s -o /dev/null -w '%{http_code}' -m 180 \
    -H "Authorization: token ${TOKEN}" "http://127.0.0.1:8888/desktop/" 2>/dev/null)"
[ "${desktop_code}" = 200 ] && pass "desktop route serves" \
    || fail "desktop route serves (HTTP ${desktop_code})"

external="$(docker exec "${NAME}" python3 -c "
ports=set()
for f in ('/proc/net/tcp','/proc/net/tcp6'):
    try:
        for line in open(f).readlines()[1:]:
            p=line.split()
            if p[3]=='0A':
                addr, port = p[1].split(':')
                if addr not in ('0100007F','00000000000000000000000001000000'):
                    ports.add(int(port,16))
    except Exception: pass
print(' '.join(str(p) for p in sorted(ports)))" 2>/dev/null)"
[ "${external}" = "8888" ] && pass "only 8888 listens externally" \
    || fail "only 8888 listens externally (got: ${external:-none})"

docker exec "${NAME}" python3 -c '
import glob, json, sys
names = {p.split("/")[-1][:-5] for p in glob.glob("/opt/scidesktop/manifest.d/*.json")}
[json.load(open(p)) for p in glob.glob("/opt/scidesktop/manifest.d/*.json")]
need = {"os-ubuntu", "startup", "jupyter-env", "selkies", "apptainer", "lmod", "sciget", "slurm"}
sys.exit(0 if need <= names else f"missing: {need - names}")' >/dev/null 2>&1 \
    && pass "version manifest complete" || fail "version manifest complete"

docker exec "${NAME}" bash -c 'for d in /usr/local/share /usr/local/bin /usr/local/etc /etc/profile.d /opt; do [ -x "$d" ] || exit 1; done' 2>/dev/null \
    && pass "shared folders traversable" || fail "shared folders traversable"

NB_USER="$(docker exec "${NAME}" printenv NB_USER 2>/dev/null || echo jovyan)"
"${HERE}/hygiene-check.sh" "${NAME}" "${NB_USER}" || FAILED=$((FAILED + 1))

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "flavour smoke: all checks passed"
else
    echo "flavour smoke: ${FAILED} check(s) failed; container log at /tmp/${NAME}.log"
fi
exit "${FAILED}"
