#!/bin/bash
# End-to-end check of an image that copies the eessi-cvmfs component.
#
#   ./test/eessi-cvmfs-smoke.sh [image]
#
# Checks EESSI CVMFS configuration, eessi-catalog, and (where /dev/fuse is
# available and SMOKE_CVMFS_MOUNT=1) mounts software.eessi.io in internal mode,
# verifies Lmod discovery of EESSI/2025.06, runs a real EESSI binary via
# eessi-launch as the notebook user, and verifies JupyterLab registers base and
# domain-specific EESSI desktop launcher tiles.

set -uo pipefail

IMAGE="${1:-scidesktop}"
NAME="eessi-cvmfs-smoke-$$"
REPOSITORY=software.eessi.io
TOKEN="eessi-cvmfs-smoke"
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
        echo "eessi-cvmfs smoke: all checks passed"
    else
        echo "eessi-cvmfs smoke: ${FAILED} check(s) failed; container log at ${LOG}"
    fi
    exit "${FAILED}"
}

as_user() { docker exec -u jovyan -w /tmp "${NAME}" bash -lc "$1" 2>&1; }

echo "eessi-cvmfs smoke: ${IMAGE}"

# Default (external) mode: software.eessi.io is configured, nothing is mounted
# when /cvmfs is empty, and eessi-catalog lists the image's launchers/modules.
out="$(docker run --rm "${IMAGE}" bash -lc "
    echo \"repositories=\${SCIDESKTOP_CVMFS_REPOSITORIES:-}\"
    cvmfs_config showconfig ${REPOSITORY} | grep -E '^CVMFS_(SERVER_URL|KEYS_DIR)='
    eessi-catalog" 2>&1)"
grep -qE "^repositories=(.*,)?${REPOSITORY}(,.*)?$" <<<"${out}" \
    && pass "internal mode includes ${REPOSITORY}" || fail "internal mode includes ${REPOSITORY}"
grep -q '^CVMFS_KEYS_DIR=/etc/cvmfs/keys/eessi\.io ' <<<"${out}" \
    && grep -qE '^CVMFS_SERVER_URL=.*eessi' <<<"${out}" \
    && pass "the client has EESSI's mirrors and key" || fail "the client has EESSI's mirrors and key"
grep -q '^\[cvmfs\] /cvmfs is empty' <<<"${out}" \
    && pass "the default mode mounts nothing" || fail "the default mode mounts nothing"
grep -q 'ParaView (EESSI)' <<<"${out}" \
    && pass "eessi-catalog lists base EESSI launchers" || fail "eessi-catalog lists base EESSI launchers"

if [ "${SMOKE_CVMFS_MOUNT:-1}" != 1 ] || [ ! -c /dev/fuse ]; then
    echo
    echo "  NOT TESTED: MOUNTING ${REPOSITORY}, LOADING EESSI/2025.06 AND EESSI LAUNCHER TILES."
    if [ "${SMOKE_CVMFS_MOUNT:-1}" != 1 ]; then
        echo "  SMOKE_CVMFS_MOUNT=${SMOKE_CVMFS_MOUNT} turned the mount off."
    else
        echo "  THIS HOST HAS NO /dev/fuse, SO A CONTAINER CANNOT MOUNT CVMFS."
    fi
    finish
fi

# Internal mode: mount software.eessi.io and start JupyterLab.
docker run -d --name "${NAME}" --user root --cap-add SYS_ADMIN --device /dev/fuse \
    --ulimit nofile=1024:4096 \
    --security-opt apparmor=unconfined --security-opt seccomp=unconfined \
    -e SCIDESKTOP_CVMFS_MODE=internal -e SCIDESKTOP_CVMFS_REPOSITORIES="${REPOSITORY}" \
    -e JUPYTER_TOKEN="${TOKEN}" "${IMAGE}" >/dev/null \
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
    finish
fi

ready=0
for _ in $(seq 1 120); do
    if docker exec "${NAME}" curl -fsS --max-time 10 -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null; then
        ready=1
        break
    fi
    sleep 1
done
if [ "${ready}" -ne 1 ]; then
    fail "notebook server responded after mounting ${REPOSITORY}"
    finish
fi
pass "notebook server responded after mounting ${REPOSITORY}"

avail="$(as_user 'module -t avail EESSI')"
if grep -q '^EESSI/2025\.06$' <<<"${avail}"; then
    pass "Lmod discovers EESSI/2025.06 from /cvmfs/software.eessi.io"
else
    fail "Lmod discovers EESSI/2025.06 from /cvmfs/software.eessi.io"
    printf '%s\n' "${avail}" | head -n 10 | sed 's/^/        /'
fi

r_out="$(as_user 'eessi-launch R R --version | head -n 1')"
if grep -q '^R version ' <<<"${r_out}"; then
    pass "eessi-launch executes EESSI R (${r_out})"
else
    fail "eessi-launch executes EESSI R"
    printf '%s\n' "${r_out}" | tail -n 10 | sed 's/^/        /'
fi

servers="$(docker exec "${NAME}" curl -fsS -H "Authorization: token ${TOKEN}" \
    "http://127.0.0.1:8888/server-proxy/servers-info" 2>/dev/null || true)"
for tile in app-eessi-paraview app-eessi-octave app-eessi-julia app-eessi-r; do
    if grep -q "\"${tile}\"" <<<"${servers}"; then
        pass "JupyterLab launcher registers ${tile}"
    else
        fail "JupyterLab launcher registers ${tile}"
    fi
done

check_domain_tile() {
    local manifest="$1" tile="$2"
    if docker exec "${NAME}" test -f "/opt/scidesktop/manifest.d/${manifest}.json" 2>/dev/null; then
        if grep -q "\"${tile}\"" <<<"${servers}"; then
            pass "domain image (${manifest}) registers ${tile}"
        else
            fail "domain image (${manifest}) registers ${tile}"
        fi
    fi
}

check_domain_tile microscopy-env app-eessi-napari
check_domain_tile datascience-env app-eessi-r-cran
check_domain_tile neuroimaging-env app-eessi-r-bioconductor

finish
