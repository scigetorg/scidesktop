#!/bin/bash
# End-to-end check of an image that copies the neurodesk-cvmfs component.
#
#   ./test/neurodesk-cvmfs-smoke.sh [image]
#
# Mounts the Neurodesk repository inside a container (internal mode), then
# finds, loads and runs a Neurodesk tool as the notebook user. This needs
# /dev/fuse on the host, a container allowed to mount, and the network to the
# Neurodesk mirrors. Where the host has no /dev/fuse the mount cannot be
# tried; the script then says NOT TESTED in capitals and checks only the
# configuration. Set SMOKE_CVMFS_MOUNT=0 to do the same on purpose.

set -uo pipefail

IMAGE="${1:-neurodesktop}"
NAME="neurodesk-cvmfs-smoke-$$"
REPOSITORY=neurodesk.ardc.edu.au
TOKEN="neurodesk-cvmfs-smoke"
LOG="/tmp/${NAME}.log"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() {
    docker logs "${NAME}" >"${LOG}" 2>&1 || true
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

finish() {
    echo
    if [ "${FAILED}" -eq 0 ]; then
        echo "neurodesk-cvmfs smoke: all checks passed"
    else
        echo "neurodesk-cvmfs smoke: ${FAILED} check(s) failed; container log at ${LOG}"
    fi
    exit "${FAILED}"
}

# Why a mount failed: the start hook does not show the client's own message.
# Tries the mount again by hand and asks each mirror for the repository's
# manifest, from inside the container.
diagnose() {
    docker exec -u root "${NAME}" bash -c "
        echo \"mount by hand: \$(mount -t cvmfs ${REPOSITORY} /cvmfs/${REPOSITORY} 2>&1 | tr '\n' ' ')\"
        echo \"/dev/fuse: \$(ls -l /dev/fuse 2>&1)\"
        echo \"capabilities: \$(grep CapEff /proc/self/status | tr '\t' ' ')\"
        echo \"cache: \$(df -T /var/lib/cvmfs 2>&1 | tail -n 1)\"
        . /etc/cvmfs/config.d/${REPOSITORY}.conf
        for url in \${CVMFS_SERVER_URL//;/ }; do
            url=\"\${url//@fqrn@/${REPOSITORY}}/.cvmfspublished\"
            echo \"\$(curl -s -o /dev/null -m 15 -w '%{http_code} in %{time_total}s' \"\${url}\") \${url}\"
        done" 2>&1 | sed 's/^/        /'
}

as_user() { docker exec -u jovyan -w /tmp "${NAME}" bash -lc "$1" 2>&1; }

echo "neurodesk-cvmfs smoke: ${IMAGE}"

# The default session: the platform mounts /cvmfs (external mode), so nothing
# is mounted here, and the client already knows the repository.
out="$(docker run --rm "${IMAGE}" bash -lc "
    echo \"repositories=\${SCIDESKTOP_CVMFS_REPOSITORIES}\"
    cvmfs_config showconfig ${REPOSITORY} | grep -E '^CVMFS_(SERVER_URL|KEYS_DIR)='" 2>&1)"
grep -qx "repositories=${REPOSITORY}" <<<"${out}" \
    && pass "internal mode would mount ${REPOSITORY}" || fail "internal mode would mount ${REPOSITORY}"
grep -q "^CVMFS_SERVER_URL=.*/cvmfs/${REPOSITORY}" <<<"${out}" && grep -q '^CVMFS_KEYS_DIR=/etc/cvmfs/keys/ardc.edu.au/' <<<"${out}" \
    && pass "the client has the repository's mirrors and key" || fail "the client has the repository's mirrors and key"
grep -q '^\[cvmfs\] /cvmfs is empty' <<<"${out}" \
    && pass "the default mode mounts nothing" || fail "the default mode mounts nothing"

if [ "${SMOKE_CVMFS_MOUNT:-1}" != 1 ] || [ ! -c /dev/fuse ]; then
    echo
    echo "  NOT TESTED: MOUNTING ${REPOSITORY} AND LOADING A NEURODESK MODULE."
    if [ "${SMOKE_CVMFS_MOUNT:-1}" != 1 ]; then
        echo "  SMOKE_CVMFS_MOUNT=${SMOKE_CVMFS_MOUNT} turned the mount off."
    else
        echo "  THIS HOST HAS NO /dev/fuse, SO A CONTAINER CANNOT MOUNT CVMFS."
    fi
    echo "  Only the configuration above was checked."
    finish
fi

# Internal mode, with what docs/operator-runbook.md says it needs. The two
# seccomp and AppArmor options are also what Apptainer needs to run the tool.
docker run -d --name "${NAME}" --user root --cap-add SYS_ADMIN --device /dev/fuse \
    --security-opt apparmor=unconfined --security-opt seccomp=unconfined \
    -e SCIDESKTOP_CVMFS_MODE=internal -e JUPYTER_TOKEN="${TOKEN}" "${IMAGE}" >/dev/null \
    || { fail "the internal-mode container starts"; finish; }
for _ in $(seq 1 180); do
    docker logs "${NAME}" >"${LOG}" 2>&1
    grep -qE "^\[cvmfs\] (mounted|failed to mount) ${REPOSITORY}" "${LOG}" && break
    sleep 1
done
if grep -q "^\[cvmfs\] mounted ${REPOSITORY}$" "${LOG}"; then
    pass "${REPOSITORY} mounts in internal mode"
else
    fail "${REPOSITORY} mounts in internal mode"
    grep '^\[cvmfs\]' "${LOG}" | sed 's/^/        /'
    diagnose
    finish
fi
for _ in $(seq 1 120); do
    docker exec "${NAME}" curl -fsS -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null && break
    sleep 1
done

# A login shell of the notebook user (a JupyterLab terminal) lists the
# Neurodesk modules by <tool>/<version>.
modules="$(as_user 'module -t avail' | grep -c '^[a-z0-9_-]*/[0-9]')"
[ "${modules}" -gt 100 ] && pass "a terminal lists ${modules} Neurodesk modules" \
    || fail "a terminal lists Neurodesk modules (found ${modules})"
docker exec "${NAME}" curl -s -H "Authorization: token ${TOKEN}" "http://127.0.0.1:8888/module/paths" 2>/dev/null \
    | grep -q "/cvmfs/${REPOSITORY}/neurodesk-modules/" \
    && pass "the Jupyter server's Lmod panel has the Neurodesk module folders" \
    || fail "the Jupyter server's Lmod panel has the Neurodesk module folders"

# Loading a module puts its tool on PATH, and the tool runs: its container is
# read from CVMFS and started by Apptainer. niimath is small and has no
# licence terms to accept. Neurodesk names a tool's arm64 container
# <tool>_arm64; the plain name is the amd64 one.
name=niimath
[ "$(docker exec "${NAME}" uname -m)" = aarch64 ] && name=niimath_arm64
module="$(as_user "module -t avail ${name}/" | grep "^${name}/" | sort -V | tail -n 1)"
if [ -z "${module}" ]; then
    fail "a ${name} module to load"
    finish
fi
tool="$(as_user "module load ${module} && command -v niimath")"
case "${tool}" in
    "/cvmfs/${REPOSITORY}/containers/"*/niimath) pass "module load ${module} puts niimath on PATH" ;;
    *) fail "module load ${module} puts niimath on PATH (got: ${tool})" ;;
esac
ran="$(as_user "module load ${module} && timeout 600 niimath" | head -n 3)"
grep -q 'niimath version' <<<"${ran}" \
    && pass "niimath runs from its container: $(grep -m 1 -o 'niimath version v[0-9.]*' <<<"${ran}")" \
    || { fail "niimath runs from its container"; printf '%s\n' "${ran}" | sed 's/^/        /'; }

finish
