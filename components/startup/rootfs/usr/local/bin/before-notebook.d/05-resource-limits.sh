# Sourced by start.sh before Jupyter starts, so what it exports reaches the
# server, its terminals and kernels.
#
# CPU_LIMIT and MEM_LIMIT, which KubeSpawner sets and jupyter-resource-usage
# reads, come from the container's cgroup when the spawner did not set them.
# Thread counts for common numerical libraries follow CPU_LIMIT unless already
# set, so tools use the pod's CPUs rather than every CPU on the node.
#
# SCIDESKTOP_CGROUP_ROOT: where to read the cgroup (default /sys/fs/cgroup).
# start.sh runs with `set -e`; every command here tolerates failure.
_sd_cg="${SCIDESKTOP_CGROUP_ROOT:-/sys/fs/cgroup}"
_sd_q="" _sd_p="" _sd_m=""
if [ -r "${_sd_cg}/cpu.max" ]; then
    read -r _sd_q _sd_p < "${_sd_cg}/cpu.max" || true
elif [ -r "${_sd_cg}/cpu/cpu.cfs_quota_us" ]; then
    _sd_q=$(cat "${_sd_cg}/cpu/cpu.cfs_quota_us" 2>/dev/null || true)
    _sd_p=$(cat "${_sd_cg}/cpu/cpu.cfs_period_us" 2>/dev/null || true)
fi
if [ -z "${CPU_LIMIT:-}" ] && [[ "${_sd_q}" =~ ^[0-9]+$ ]] && [[ "${_sd_p}" =~ ^[1-9][0-9]*$ ]]; then
    export CPU_LIMIT=$(( (_sd_q + _sd_p - 1) / _sd_p ))
fi
if [ -r "${_sd_cg}/memory.max" ]; then
    _sd_m=$(cat "${_sd_cg}/memory.max" 2>/dev/null || true)
elif [ -r "${_sd_cg}/memory/memory.limit_in_bytes" ]; then
    _sd_m=$(cat "${_sd_cg}/memory/memory.limit_in_bytes" 2>/dev/null || true)
fi
# cgroup v1 reports "unlimited" as a huge number.
if [ -z "${MEM_LIMIT:-}" ] && [[ "${_sd_m}" =~ ^[0-9]+$ ]] && [ "${#_sd_m}" -lt 19 ]; then
    export MEM_LIMIT="${_sd_m}"
fi
if [ -n "${CPU_LIMIT:-}" ]; then
    # KubeSpawner may pass a fraction ("1.5"); thread counts need a whole number.
    _sd_n=$(awk -v c="${CPU_LIMIT}" 'BEGIN { n = int(c); if (n < c) n++; if (n < 1) n = 1; print n }' 2>/dev/null || true)
    if [ -n "${_sd_n}" ]; then
        for _sd_v in OMP_NUM_THREADS MKL_NUM_THREADS OPENBLAS_NUM_THREADS NUMEXPR_NUM_THREADS; do
            [ -n "${!_sd_v:-}" ] || export "${_sd_v}=${_sd_n}"
        done
    fi
    echo "[resources] CPU_LIMIT=${CPU_LIMIT} MEM_LIMIT=${MEM_LIMIT:-unset} threads=${_sd_n:-unset}"
fi
unset _sd_cg _sd_q _sd_p _sd_m _sd_n _sd_v
