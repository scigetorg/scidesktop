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
while IFS='=' read -r _sd_k _sd_v; do
    case "${_sd_k}" in
        CPU_LIMIT|MEM_LIMIT) [ -n "${_sd_v}" ] && export "${_sd_k}=${_sd_v}" ;;
    esac
done < <(/opt/scidesktop/resource-limits 2>/dev/null || true)
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
if [ -z "${MPLCONFIGDIR:-}" ] && [ -n "${HOME:-}" ]; then
    export MPLCONFIGDIR="${HOME}/.config/matplotlib-mpldir"
fi
unset _sd_k _sd_v _sd_n
