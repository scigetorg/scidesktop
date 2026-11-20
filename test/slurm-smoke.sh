#!/bin/bash
# End-to-end check of the session's Slurm queue (components/slurm).
#
#   ./test/slurm-smoke.sh [image]
#
# Runs sessions the way a JupyterHub pod does: as the notebook user, with no
# added capability, under CPU and memory limits. A batch job must run to
# completion; nothing may listen beyond loopback but the notebook server.

set -uo pipefail

IMAGE="${1:-scidesktop}"
NAME="slurm-smoke-$$"
TOKEN="slurm-smoke"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() {
    rm -f "/tmp/${NAME}.log"
    docker rm -f "${NAME}" "${NAME}-root" "${NAME}-off" >/dev/null 2>&1 || true
}
trap cleanup EXIT

as_user() { docker exec -u jovyan -w /tmp "$1" bash -lc "$2" 2>&1; }

# logged <container> <pattern>: the log is saved before it is searched.
logged() {
    docker logs "$1" >"/tmp/${NAME}.log" 2>&1
    grep -qE "$2" "/tmp/${NAME}.log"
}

# run_job <container>: submits a batch job with a step in it and prints its
# final state and output.
run_job() {
    as_user "$1" '
        cat > job.sh <<"JOB"
#!/bin/bash
echo "user=$(id -un) cpus=${SLURM_CPUS_ON_NODE}"
srun --ntasks=1 echo step-ran
JOB
        job="$(sbatch --parsable --output=/tmp/job-%j.out job.sh)" || exit 1
        for _ in $(seq 90); do
            state="$(scontrol show job "${job}" | grep -o "JobState=[A-Z]*")"
            case "${state}" in JobState=COMPLETED|JobState=FAILED|JobState=CANCELLED) break ;; esac
            sleep 1
        done
        echo "${state}"; cat "/tmp/job-${job}.out"'
}

echo "slurm smoke: ${IMAGE}"
docker run -d --name "${NAME}" --cpus=2 --memory=2g --shm-size=1g \
    -e JUPYTER_TOKEN="${TOKEN}" "${IMAGE}" >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }
for _ in $(seq 1 120); do
    docker exec "${NAME}" curl -fsS -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null && break
    sleep 1
done
as_user "${NAME}" '/opt/slurm/bin/slurm-session wait' >/dev/null

# The queue is the container's size, less the session's reserve, and the
# daemons run as the notebook user.
[ "$(as_user "${NAME}" 'sinfo -h -o "%P %c %m %T"')" = "scidesktop* 2 1536 idle" ] \
    && pass "the queue has the container's 2 CPUs and its memory less the reserve" \
    || fail "the queue has the container's 2 CPUs and its memory less the reserve (got: $(as_user "${NAME}" 'sinfo -h -o "%P %c %m %T"'))"
owners="$(docker exec "${NAME}" ps -o user= -C slurmctld,slurmd | sort -u | tr -d ' ')"
[ "${owners}" = jovyan ] && pass "slurmctld and slurmd run as the notebook user" \
    || fail "slurmctld and slurmd run as the notebook user (got: ${owners:-none})"
[ "$(docker exec "${NAME}" sh -c 'cat /proc/1/status' | awk '/^CapEff:/ { print $2 }')" = 0000000000000000 ] \
    && pass "the session holds no capability" || fail "the session holds no capability"

out="$(run_job "${NAME}")"
[ "${out}" = "$(printf 'JobState=COMPLETED\nuser=jovyan cpus=1\nstep-ran')" ] \
    && pass "sbatch runs a job to completion as the notebook user" \
    || { fail "sbatch runs a job to completion as the notebook user"; printf '%s\n' "${out}" | sed 's/^/        /'; }
[ "$(as_user "${NAME}" 'srun --ntasks=1 --cpus-per-task=2 nproc --all >/dev/null && srun --ntasks=1 echo interactive')" = interactive ] \
    && pass "srun runs a command" || fail "srun runs a command"

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
docker exec "${NAME}" sh -c '[ "$(stat -c "%U %a" /run/slurm/conf/slurm.key)" = "jovyan 600" ]' \
    && pass "the queue's key is private to the user" || fail "the queue's key is private to the user"

# A stop ends the daemons in order, within Docker's default grace period.
docker stop "${NAME}" >/dev/null
logged "${NAME}" '^\[slurm\] stopped$' && [ "$(docker inspect "${NAME}" --format '{{.State.ExitCode}}')" = 0 ] \
    && pass "the queue stops cleanly with the container" \
    || fail "the queue stops cleanly with the container"
# The same container started again has a queue again, and no stale state.
docker start "${NAME}" >/dev/null
for _ in $(seq 1 120); do
    docker exec "${NAME}" curl -fsS -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null && break
    sleep 1
done
as_user "${NAME}" '/opt/slurm/bin/slurm-session wait' >/dev/null
out="$(run_job "${NAME}")"
[ "$(head -n 1 <<<"${out}")" = JobState=COMPLETED ] && pass "a restarted container has a working queue" \
    || { fail "a restarted container has a working queue"; printf '%s\n' "${out}" | sed 's/^/        /'; }
docker rm -f "${NAME}" >/dev/null

# Started as root (a deployment that changes the user at start): the queue
# and its jobs still belong to the notebook user.
docker run -d --name "${NAME}-root" --user root -e JUPYTER_TOKEN="${TOKEN}" "${IMAGE}" >/dev/null
for _ in $(seq 1 120); do
    docker exec "${NAME}-root" curl -fsS -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null && break
    sleep 1
done
as_user "${NAME}-root" '/opt/slurm/bin/slurm-session wait' >/dev/null
out="$(run_job "${NAME}-root")"
owners="$(docker exec "${NAME}-root" ps -o user= -C slurmctld,slurmd | sort -u | tr -d ' ')"
[ "$(head -n 2 <<<"${out}")" = "$(printf 'JobState=COMPLETED\nuser=jovyan cpus=1')" ] && [ "${owners}" = jovyan ] \
    && pass "a container started as root runs the queue and its jobs as the notebook user" \
    || { fail "a container started as root runs the queue and its jobs as the notebook user"; printf '%s\n' "${out}" | sed 's/^/        /'; }
docker rm -f "${NAME}-root" >/dev/null

# Off on request.
docker run -d --name "${NAME}-off" -e SCIDESKTOP_SLURM=no -e JUPYTER_TOKEN="${TOKEN}" "${IMAGE}" >/dev/null
for _ in $(seq 1 120); do
    docker exec "${NAME}-off" curl -fsS -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null && break
    sleep 1
done
if logged "${NAME}-off" '^\[slurm\]' || docker exec "${NAME}-off" pgrep -x slurmctld >/dev/null; then
    fail "SCIDESKTOP_SLURM=no starts nothing"
else
    pass "SCIDESKTOP_SLURM=no starts nothing"
fi

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "slurm smoke: all checks passed"
else
    echo "slurm smoke: ${FAILED} check(s) failed"
fi
exit "${FAILED}"
