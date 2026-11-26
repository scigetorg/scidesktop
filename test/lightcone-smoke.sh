#!/bin/bash
# End-to-end check of Lightcone on the session's Slurm queue
# (components/lightcone).
#
#   ./test/lightcone-smoke.sh [image]
#
# The container has 4 GB, so its queue's node is smaller than the 2-CPU,
# 8-GiB shape a fixed catalog would ask for (neurodesk/neurodesktop#1393).
# lc must still launch on it, run, materialize an output, skip unchanged work,
# rebuild after a spec change and release the allocation.

set -uo pipefail

IMAGE="${1:-scidesktop}"
NAME="lightcone-smoke-$$"
TOKEN="lightcone-smoke"

cleanup() { docker rm -f "${NAME}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "lightcone smoke: ${IMAGE}"
docker run -d --name "${NAME}" --memory=4g --shm-size=1g \
    -e JUPYTER_TOKEN="${TOKEN}" "${IMAGE}" >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }
for _ in $(seq 1 120); do
    docker exec "${NAME}" curl -fsS -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null && break
    sleep 1
done
docker exec -u jovyan "${NAME}" /opt/slurm/bin/slurm-session wait >/dev/null \
    || { echo "  FAIL  the session's queue is not ready"; exit 1; }

docker exec -i -u jovyan -w /tmp "${NAME}" bash -l <<'FLOW'
set -uo pipefail
FAILED=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }
json() { /opt/lightcone/bin/python -c "import json, sys; d = json.load(sys.stdin); print($1)"; }

# lc chooses the standard shape at the queue's size: here the node's memory.
read -r cpus memory < <(lc compute resources --json \
    | json '" ".join(str(x) for x in (d["offers"][0]["resources"]["cpus"], int(d["offers"][0]["resources"]["memory"] * 1024)))')
read -r node_cpus node_memory < <(sinfo -h -o '%c %m' | head -1)
want_cpus=$(( node_cpus < 2 ? node_cpus : 2 ))
want_memory=$(( node_memory < 8192 ? node_memory : 8192 ))
[ "${cpus} ${memory}" = "${want_cpus} ${want_memory}" ] && [ "${node_memory}" -lt 8192 ] \
    && pass "the standard offer fits the ${node_memory} MB node: ${cpus} CPUs, ${memory} MB" \
    || fail "the standard offer fits the node (offer: ${cpus:-?} CPUs ${memory:-?} MB; node: ${node_cpus} CPUs ${node_memory} MB)"

root="$(mktemp -d)/analysis"
mkdir -p "${root}" && cd "${root}" || exit 1
git init -q && git config user.name "scidesktop smoke" && git config user.email smoke@scidesktop.invalid
commit() { git add -A && git commit -qm "$1"; }
if lc init . --json >/tmp/lc-init.log 2>&1; then
    pass "lc init makes a project"
else
    fail "lc init makes a project"; sed 's/^/        /' /tmp/lc-init.log; exit 1
fi
sed -i 's/^\[project\]$/[project]\nlicense = "MIT"/' pyproject.toml
cat > astra.yaml <<'SPEC'
version: "0.0.14"
name: "scidesktop smoke"
inputs: []
outputs:
  - id: answer
    type: data
    format: txt
    recipe:
      command: "python -c \"from pathlib import Path; Path('{output}').write_text('42')\""
      resources: {cpus: 1, memory: "1Gi"}
SPEC
commit "Define the answer"

cluster="$(lc compute launch --cpus "${cpus}" --memory "${memory}MB" --json | json 'd["id"]')"
[ -n "${cluster}" ] && pass "lc compute launch submits an allocation" \
    || { fail "lc compute launch submits an allocation"; exit 1; }
if lc compute status "${cluster}" --wait --json >/tmp/lc-status.log 2>&1; then
    pass "the allocation starts on the queue"
else
    fail "the allocation starts on the queue"; sed 's/^/        /' /tmp/lc-status.log
    squeue -a -o '%i %T %r' | sed 's/^/        /'
fi
[ "$(lc run "${cluster}" -- python -c "print('ready')" 2>/tmp/lc-run.log)" = ready ] \
    && pass "lc run runs a command on it" || { fail "lc run runs a command on it"; sed 's/^/        /' /tmp/lc-run.log; }
lc materialize "${cluster}" baseline/answer >/tmp/lc-mat.log 2>&1
[ "$(cat results/baseline/answer.txt 2>/dev/null)" = 42 ] \
    && pass "lc materialize writes the output" || { fail "lc materialize writes the output"; sed 's/^/        /' /tmp/lc-mat.log; }
before="$(sha256sum results/baseline/.answer.manifest.json 2>/dev/null)"
lc materialize "${cluster}" baseline/answer >/dev/null 2>&1
[ -n "${before}" ] && [ "$(sha256sum results/baseline/.answer.manifest.json)" = "${before}" ] \
    && lc materialize --check baseline/answer >/dev/null 2>&1 \
    && pass "an unchanged output is not rebuilt" || fail "an unchanged output is not rebuilt"
sed -i 's/42/43/' astra.yaml && commit "Change the answer"
[ "$(lc status --json | json 'd["outputs"][0]["status"]')" = stale ] \
    && pass "a spec change makes the output stale" || fail "a spec change makes the output stale"
lc materialize "${cluster}" baseline/answer >/tmp/lc-mat.log 2>&1
[ "$(cat results/baseline/answer.txt)" = 43 ] \
    && pass "lc materialize rebuilds it" || { fail "lc materialize rebuilds it"; sed 's/^/        /' /tmp/lc-mat.log; }

lc compute down "${cluster}" --json >/dev/null 2>&1
phase=""
for _ in $(seq 60); do
    phase="$(lc compute status "${cluster}" --json 2>/dev/null | json 'd["phase"]')"
    [ "${phase}" = ended ] && break
    sleep 1
done
[ "${phase}" = ended ] && pass "lc compute down releases the allocation" \
    || fail "lc compute down releases the allocation (phase: ${phase:-unknown})"
exit "${FAILED}"
FLOW
FAILED=$?

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "lightcone smoke: all checks passed"
else
    echo "lightcone smoke: ${FAILED} check(s) failed"
fi
exit "${FAILED}"
