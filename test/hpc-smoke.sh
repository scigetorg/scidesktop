#!/bin/bash
# End-to-end check of foreign-UID / HPC startup modes (no root startup, no
# capabilities, default Docker seccomp/AppArmor, fresh mounted home):
#   1. OpenShift / Kubernetes foreign UID (--user 12345:0 --group-add 100):
#      start.sh registers UID 12345 in /etc/passwd; Slurm detects that UID
#      12345 does not own /run/slurm and skips cleanly without hanging;
#      container stops cleanly with exit 0.
#   2. Strict unprivileged HPC foreign UID (--user 12345:12345, no /etc/passwd
#      entry, no group 100, mounted home at /home/hpc): Jupyter, login shell,
#      home defaults, desktop (Selkies/Xvfb/IceWM/PipeWire), T3 Code, and
#      code-server all work, only port 8888 listens beyond loopback, and
#      container stops cleanly with exit 0.
#
#   ./test/hpc-smoke.sh [image]

set -uo pipefail

IMAGE="${1:-scidesktop}"
NAME="hpc-smoke-$$"
VOL1="${NAME}-k8s-home"
VOL2="${NAME}-strict-home"
TOKEN="hpc-smoke"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() {
    docker logs "${NAME}-k8s" >"/tmp/${NAME}-k8s.log" 2>&1 || true
    docker logs "${NAME}-strict" >"/tmp/${NAME}-strict.log" 2>&1 || true
    docker rm -f "${NAME}-k8s" "${NAME}-strict" >/dev/null 2>&1 || true
    docker volume rm -f "${VOL1}" "${VOL2}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_jupyter() {
    local c="$1"
    for _ in $(seq 1 120); do
        docker exec "${c}" curl -fsS -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null && return 0
        sleep 1
    done
    return 1
}

check_loopback_only() {
    local c="$1" label="$2" external
    external="$(docker exec "${c}" python3 -c "
ports = set()
for f in ('/proc/net/tcp', '/proc/net/tcp6'):
    for line in open(f).readlines()[1:]:
        p = line.split()
        addr, port = p[1].split(':')
        if p[3] == '0A' and addr not in ('0100007F', '00000000000000000000000001000000'):
            ports.add(int(port, 16))
print(' '.join(str(p) for p in sorted(ports)))" 2>/dev/null)"
    [ "${external}" = "8888" ] && pass "${label}: only 8888 listens beyond loopback" \
        || fail "${label}: only 8888 listens beyond loopback (got: ${external:-none})"
}

echo "hpc smoke: ${IMAGE}"

# ---------------------------------------------------------------------------
# Mode 1: OpenShift / Kubernetes foreign UID (--user 12345:0 --group-add 100)
# ---------------------------------------------------------------------------
docker volume create "${VOL1}" >/dev/null \
    && docker run --rm --user 0 -v "${VOL1}:/home/jovyan" --entrypoint sh "${IMAGE}" \
        -c 'chown 12345:100 /home/jovyan && chmod 0755 /home/jovyan' >/dev/null \
    || { echo "  FAIL  could not prepare k8s foreign-UID volume"; exit 1; }

docker run -d --name "${NAME}-k8s" --user 12345:0 --group-add 100 \
    --cpus=2 --memory=2g --shm-size=1g \
    -v "${VOL1}:/home/jovyan" \
    -e JUPYTER_TOKEN="${TOKEN}" \
    "${IMAGE}" >/dev/null || { echo "  FAIL  k8s container did not start"; exit 1; }

if wait_jupyter "${NAME}-k8s"; then
    pass "k8s foreign UID (12345:0 + group 100): jupyter responds"
else
    fail "k8s foreign UID (12345:0 + group 100): jupyter responds"
    docker logs "${NAME}-k8s" 2>&1 | tail -n 30 | sed 's/^/        /'
fi

[ "$(docker exec "${NAME}-k8s" id -u 2>/dev/null)" = "12345" ] \
    && pass "k8s: running as UID 12345" || fail "k8s: running as UID 12345"
[ "$(docker exec "${NAME}-k8s" awk '/^CapEff:/ { print $2 }' /proc/1/status 2>/dev/null)" = "0000000000000000" ] \
    && pass "k8s: holds no capabilities" || fail "k8s: holds no capabilities"
docker exec "${NAME}-k8s" sh -c 'pid=$(pgrep -o -f "[j]upyter-lab|[j]upyter lab"); [ -n "${pid}" ] && grep -qx "NoNewPrivs:[[:space:]]*1" "/proc/${pid}/status"' 2>/dev/null \
    && pass "k8s: Jupyter server runs with NoNewPrivs=1" \
    || fail "k8s: Jupyter server runs with NoNewPrivs=1"
docker exec "${NAME}-k8s" grep -q ':12345:' /etc/passwd 2>/dev/null \
    && pass "k8s: start.sh registered UID 12345 in /etc/passwd" \
    || fail "k8s: start.sh registered UID 12345 in /etc/passwd"

# Without root startup, /run/slurm is owned by UID 1000 so Slurm's own
# _prepare_run_dir would reject UID 12345; slurm-session must detect this
# upfront and exit cleanly without spinning.
sleep 2
docker logs "${NAME}-k8s" >"/tmp/${NAME}-k8s.log" 2>&1
if grep -q '\[slurm\] not started:.*does not own and write /run/slurm' "/tmp/${NAME}-k8s.log" \
    && ! docker exec "${NAME}-k8s" pgrep -x slurmctld >/dev/null 2>&1 \
    && ! docker exec "${NAME}-k8s" pgrep -x slurmd >/dev/null 2>&1; then
    pass "k8s: slurm skips cleanly without hanging when /run/slurm is owned by another UID"
else
    fail "k8s: slurm skips cleanly without hanging when /run/slurm is owned by another UID"
    grep -i slurm "/tmp/${NAME}-k8s.log" | tail -n 10 | sed 's/^/        /'
fi

check_loopback_only "${NAME}-k8s" "k8s"
docker stop "${NAME}-k8s" >/dev/null
[ "$(docker inspect "${NAME}-k8s" --format '{{.State.ExitCode}}')" = "0" ] \
    && pass "k8s: stops cleanly (exit 0)" \
    || fail "k8s: stops cleanly (exit $(docker inspect "${NAME}-k8s" --format '{{.State.ExitCode}}'))"
docker rm -f "${NAME}-k8s" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Mode 2: Strict HPC foreign UID (--user 12345:12345, no /etc/passwd, no gid 100)
# ---------------------------------------------------------------------------
# Images with ai-ready run PostgreSQL initdb at startup, which requires an
# /etc/passwd entry (covered by Mode 1 above with --user 12345:0).
if docker run --rm --entrypoint test "${IMAGE}" -f /opt/scidesktop/manifest.d/ai-ready.json 2>/dev/null; then
    pass "strict HPC (no /etc/passwd): skipped on ai-ready image (PostgreSQL initdb requires --user <uid>:0, tested above)"
else
    docker volume create "${VOL2}" >/dev/null \
        && docker run --rm --user 0 -v "${VOL2}:/home/jovyan" --entrypoint sh "${IMAGE}" \
            -c 'chown 12345:12345 /home/jovyan && chmod 0755 /home/jovyan' >/dev/null \
        || { echo "  FAIL  could not prepare strict foreign-UID volume"; exit 1; }

    docker run -d --name "${NAME}-strict" --user 12345:12345 \
        --cpus=2 --memory=2g --shm-size=1g \
        -v "${VOL2}:/home/jovyan" \
        -e HOME=/home/jovyan \
        -e JUPYTER_TOKEN="${TOKEN}" \
        "${IMAGE}" >/dev/null || { echo "  FAIL  strict HPC container did not start"; exit 1; }

    if wait_jupyter "${NAME}-strict"; then
        pass "strict HPC UID (12345:12345): jupyter responds"
    else
        fail "strict HPC UID (12345:12345): jupyter responds"
        docker logs "${NAME}-strict" 2>&1 | tail -n 30 | sed 's/^/        /'
    fi

    out="$(docker exec -u 12345:12345 -e HOME=/home/jovyan -w /home/jovyan "${NAME}-strict" \
        bash -lc 'type -t module >/dev/null && type -t mamba >/dev/null && sciget catalog list >/dev/null && echo HPC_SHELL_OK' 2>&1)"
    grep -qx 'HPC_SHELL_OK' <<<"${out}" \
        && pass "strict HPC: login shell has module, mamba, and sciget" \
        || { fail "strict HPC: login shell has module, mamba, and sciget"; printf '%s\n' "${out}" | head -n 10 | sed 's/^/        /'; }

    seeded="$(docker exec -u 12345:12345 -e HOME=/home/jovyan -w /home/jovyan "${NAME}-strict" \
        bash -lc 'for f in .codex/config.toml .claude/settings.json .config/opencode/opencode.json; do [ -r "${HOME}/${f}" ] || { echo "missing:${f}"; exit 1; }; done; echo SEEDED_OK' 2>&1)"
    grep -qx 'SEEDED_OK' <<<"${seeded}" \
        && pass "strict HPC: home defaults seeded into mounted foreign-UID home" \
        || fail "strict HPC: home defaults seeded (${seeded})"

    # Desktop route starts Selkies, Xvfb, IceWM, PipeWire under strict foreign UID.
    code="$(docker exec "${NAME}-strict" curl -s -o /dev/null -w '%{http_code}' -m 180 \
        -H "Authorization: token ${TOKEN}" "http://127.0.0.1:8888/desktop/")"
    [ "${code}" = "200" ] && pass "strict HPC: desktop route serves" \
        || fail "strict HPC: desktop route serves (HTTP ${code})"
    for proc in Xvfb icewm pipewire; do
        docker exec "${NAME}-strict" pgrep -x "${proc}" >/dev/null 2>&1 \
            && pass "strict HPC: ${proc} running" \
            || fail "strict HPC: ${proc} running"
    done

    # T3 Code serves behind auth under strict foreign UID (first request returns
    # 503 + Refresh while T3 cold-starts, then 200 once ready).
    code=""
    for _ in $(seq 1 30); do
        code="$(docker exec "${NAME}-strict" curl -s -o /dev/null -w '%{http_code}' -m 30 \
            -H "Authorization: token ${TOKEN}" "http://127.0.0.1:8888/t3-code/")"
        [ "${code}" = "200" ] && break
        sleep 1
    done
    [ "${code}" = "200" ] && pass "strict HPC: t3-code serves" \
        || fail "strict HPC: t3-code serves (HTTP ${code})"

    # If code-server is present, VS Code serves behind auth under strict foreign UID.
    if docker exec "${NAME}-strict" test -f /opt/scidesktop/manifest.d/code-server.json 2>/dev/null; then
        code="$(docker exec "${NAME}-strict" curl -s -L -o /dev/null -w '%{http_code}' -m 120 \
            -H "Authorization: token ${TOKEN}" "http://127.0.0.1:8888/vscode/")"
        [ "${code}" = "200" ] && pass "strict HPC: code-server serves" \
            || fail "strict HPC: code-server serves (HTTP ${code})"
    fi

    check_loopback_only "${NAME}-strict" "strict HPC"
    docker stop "${NAME}-strict" >/dev/null
    [ "$(docker inspect "${NAME}-strict" --format '{{.State.ExitCode}}')" = "0" ] \
        && pass "strict HPC: stops cleanly (exit 0)" \
        || fail "strict HPC: stops cleanly (exit $(docker inspect "${NAME}-strict" --format '{{.State.ExitCode}}'))"
fi

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "hpc smoke: all checks passed"
else
    echo "hpc smoke: ${FAILED} check(s) failed; logs at /tmp/${NAME}-{k8s,strict}.log"
fi
exit "${FAILED}"
