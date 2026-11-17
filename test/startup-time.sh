#!/bin/bash
# Startup time breakdown, from container start to Jupyter answering.
#
#   ./test/startup-time.sh [image] [runs] [docker run args...]
#
# Phases, from `docker logs -t`:
#   entrypoint  container start  -> "Entered start.sh"
#   start.sh    "Entered start.sh" -> "Executing the command" or, when started
#               as root, "Running as <user>" (includes hooks)
#   jupyter     "Executing the command" -> "is running at"
#   ready       container start  -> first 200 from /api
# Prints each run and the median of each phase.
set -uo pipefail
IMAGE="${1:-scidesktop}"
RUNS="${2:-5}"
shift 2 2>/dev/null || shift $#
PORT="${STARTUP_PORT:-18991}"

ts() { date -d "$1" +%s.%N; }
line_ts() { docker logs -t "$1" 2>&1 | grep -m1 -E "$2" | cut -d' ' -f1; }

results=()
for run in $(seq 1 "${RUNS}"); do
    name="scidesktop-startup-$$-${run}"
    docker run -d --name "${name}" -p "127.0.0.1:${PORT}:8888" --shm-size=2g \
        -e JUPYTER_TOKEN=t "$@" "${IMAGE}" >/dev/null || { echo "run ${run}: failed to start"; exit 1; }
    ready=""
    for _ in $(seq 1 600); do
        if curl -fsS -o /dev/null "http://127.0.0.1:${PORT}/api" 2>/dev/null; then
            ready=$(date -u +%Y-%m-%dT%H:%M:%S.%NZ); break
        fi
        sleep 0.05
    done
    started=$(docker inspect -f '{{.State.StartedAt}}' "${name}")
    entered=$(line_ts "${name}" "Entered start.sh")
    executing=$(line_ts "${name}" "Executing the command|Running as ")
    running=$(line_ts "${name}" "is running at")
    docker rm -f "${name}" >/dev/null
    if [ -z "${ready}" ] || [ -z "${entered}" ] || [ -z "${executing}" ] || [ -z "${running}" ]; then
        echo "run ${run}: missing a phase marker (ready=${ready:-none})"; continue
    fi
    r=$(awk -v s="$(ts "${started}")" -v e="$(ts "${entered}")" -v x="$(ts "${executing}")" \
            -v j="$(ts "${running}")" -v d="$(ts "${ready}")" \
            'BEGIN { printf "%.3f %.3f %.3f %.3f", e-s, x-e, j-x, d-s }')
    results+=("${r}")
    printf 'run %d: entrypoint %s  start.sh %s  jupyter %s  ready %s\n' "${run}" ${r}
done

[ "${#results[@]}" -gt 0 ] || exit 1
printf '%s\n' "${results[@]}" | awk '
    { for (i = 1; i <= 4; i++) v[i][NR] = $i }
    END {
        split("entrypoint start.sh jupyter ready", n, " ")
        printf "median:"
        for (i = 1; i <= 4; i++) {
            m = NR; for (k = 1; k <= m; k++) a[k] = v[i][k]
            asort(a); med = (m % 2) ? a[(m + 1) / 2] : (a[m / 2] + a[m / 2 + 1]) / 2
            printf " %s %.3f ", n[i], med; delete a
        }
        printf "\n"
    }'
