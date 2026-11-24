#!/bin/bash
# The component's own test: runs on the OS layer as the notebook user.
set -euo pipefail
session=/opt/slurm/bin/slurm-session
log=/tmp/slurm-session.log

[ "$(id -u)" != 0 ]
[ "$(stat -c '%U %a' /run/slurm /run/slurmctld)" = "$(printf '%s 775\n%s 775' "$(id -un)" "$(id -un)")" ]
[ "$(readlink /etc/slurm/slurm.conf)" = /run/slurm/conf/slurm.conf ]

# Ports of this test's own: on some builders the tests of several components
# run at once and share one network.
controller_port="$(shuf -i 20000-39999 -n 1)"
worker_port="$(( controller_port + 20000 ))"
export SCIDESKTOP_SLURM_PORTS="${controller_port},${worker_port}"

# The queue is sized from the container's limits, less the session's reserve.
CPU_LIMIT=1.5 MEM_LIMIT=$(( 2048 * 1048576 )) "${session}" run >"${log}" 2>&1 &
supervisor=$!
trap 'kill "${supervisor}" 2>/dev/null || true; cat "${log}"; tail -n 20 /run/slurm/log/*.log 2>/dev/null || true' ERR
"${session}" wait
grep -q "queue scidesktop: 2 CPUs, 1536 MB" "${log}"
[ "$(sinfo -h -o '%P %c %m %T')" = "scidesktop* 2 1536 idle" ]
[ "$(stat -c %a /run/slurm/conf/slurm.key)" = 600 ]

# Both daemons listen, on loopback only.
ports="$(printf ':%04X$|:%04X$' "${controller_port}" "${worker_port}")"
listening="$(awk 'NR > 1 && $4 == "0A" { print $2 }' /proc/net/tcp /proc/net/tcp6 | grep -E "${ports}" | sort -u)"
[ "$(wc -l <<<"${listening}")" = 2 ]
if grep -v -E '^(0100007F|00000000000000000000000001000000):' <<<"${listening}"; then
    echo "a Slurm daemon listens beyond loopback" >&2
    exit 1
fi

# A batch job runs to completion as the notebook user, with a step in it,
# and a job does not inherit the daemons' preloaded library.
cd /tmp
cat > job.sh <<'JOB'
#!/bin/bash
echo "user=$(id -un) cpus=${SLURM_CPUS_ON_NODE} preload=[${LD_PRELOAD:-}]"
srun --ntasks=1 echo step-ran
JOB
job="$(sbatch --parsable --output=/tmp/job-%j.out job.sh)"
for _ in $(seq 60); do
    state="$(scontrol show job "${job}" | grep -o 'JobState=[A-Z]*')"
    case "${state}" in JobState=COMPLETED|JobState=FAILED|JobState=CANCELLED) break ;; esac
    sleep 1
done
[ "${state}" = JobState=COMPLETED ]
[ "$(cat "/tmp/job-${job}.out")" = "$(printf 'user=%s cpus=1 preload=[]\nstep-ran' "$(id -un)")" ]
[ "$(srun --ntasks=1 echo interactive)" = interactive ]

# SIGTERM stops the worker, then the controller, and the supervisor exits.
kill -TERM "${supervisor}"
wait "${supervisor}"
grep -qx '\[slurm\] stopped' "${log}"
if pgrep -x slurmd >/dev/null || pgrep -x slurmctld >/dev/null; then
    echo "a Slurm daemon outlived its supervisor" >&2
    exit 1
fi
trap - ERR

# The start hook leaves a session alone that says no, or has a cluster.
hook=/usr/local/bin/before-notebook.d/50-slurm.sh
[ -z "$(SCIDESKTOP_SLURM=no bash -c ". ${hook}; echo \"\${SCIDESKTOP_SLURM_SUPERVISOR_PID:-}\"")" ]
SLURM_CONF=/etc/hpc/slurm.conf bash -c ". ${hook}" | grep -q "using that cluster"

# External-cluster MUNGE client plugins are compiled in and loadable when
# SLURM_CONF points at a MUNGE-authenticated site cluster, even without a
# local munged daemon.
test -r /opt/slurm/lib/slurm/auth_munge.so
test -r /opt/slurm/lib/slurm/cred_munge.so
test -r /opt/slurm/share/licenses/slurm/COPYING
test -r /opt/slurm/share/licenses/slurm/LICENSE.OpenSSL
munge_conf="$(mktemp)"
cat > "${munge_conf}" <<'CONF'
ClusterName=external
SlurmctldHost=127.0.0.1
AuthType=auth/munge
CredType=cred/munge
NodeName=n1
PartitionName=p1 Nodes=n1 Default=YES State=UP
CONF
munge_err="$(SLURM_CONF="${munge_conf}" sinfo 2>&1 || true)"
rm -f "${munge_conf}"
if grep -qiE "unable to (find|load) plugin|cannot open shared object" <<<"${munge_err}"; then
    echo "MUNGE plugin failed to load: ${munge_err}" >&2
    exit 1
fi

# Nothing root-owned is writable by group or others.
if find /opt/slurm /etc/slurm /usr/local/bin/before-notebook.d/50-slurm.sh /etc/scidesktop/jupyter_server_config.d/slurm.py ! -type l -perm /022 -print | grep .; then
    echo "bad permissions on the files above" >&2
    exit 1
fi
echo "slurm: a job ran as $(id -un) on a loopback-only queue"
