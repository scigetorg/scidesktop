#!/bin/bash
# End-to-end check of an image that copies the eessi-cvmfs component.
#
#   ./test/eessi-cvmfs-smoke.sh [image]
#
# Checks EESSI CVMFS configuration, eessi-catalog, and (where /dev/fuse is
# available and SMOKE_CVMFS_MOUNT=1) mounts software.eessi.io in internal mode,
# verifies Lmod discovery of EESSI/2025.06, runs a real EESSI binary via
# eessi-launch as the notebook user, and verifies JupyterLab registers base
# EESSI desktop launcher tiles (domain-specific tiles are checked by each
# domain environment's own smoke test).

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
bad_execs="$(docker run --rm --entrypoint bash "${IMAGE}" -c '
    for f in /etc/scidesktop/eessi-apps.d/*.desktop; do
        [ -f "${f}" ] || continue
        exec_line="$(sed -n "s/^Exec=//p" "${f}" | head -n 1)"
        case "${exec_line}" in
            *xfce4-terminal*)
                case "${exec_line}" in
                    *--disable-server*) ;;
                    *) echo "${f}: ${exec_line}" ;;
                esac
                ;;
        esac
    done
' 2>&1)"
if [ -z "${bad_execs}" ]; then
    pass "all xfce4-terminal EESSI desktop launchers pass --disable-server"
else
    fail "all xfce4-terminal EESSI desktop launchers pass --disable-server (${bad_execs})"
fi

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

# Verify an EESSI xfce4-terminal desktop launcher preserves its EESSI PATH even
# when an ordinary xfce4-terminal server is already running on the D-Bus session.
term_out="$(as_user '
    set -euo pipefail
    out_file="/tmp/eessi-term-r-$$.txt"
    rm -f "${out_file}"
    Xvfb :77 -screen 0 1024x768x24 >/dev/null 2>&1 &
    xvfb_pid=$!
    term_pid=""
    cleanup_x() {
        [ -n "${term_pid}" ] && kill "${term_pid}" 2>/dev/null || true
        kill "${xvfb_pid}" 2>/dev/null || true
        rm -f "${out_file}"
    }
    trap cleanup_x EXIT
    export DISPLAY=:77
    for _ in $(seq 1 30); do
        [ -S /tmp/.X11-unix/X77 ] && break
        sleep 0.2
    done
    eval "$(/usr/bin/dbus-launch --sh-syntax --exit-with-x11)"
    xfce4-terminal -e "sleep 60" >/dev/null 2>&1 &
    term_pid=$!
    dbus_ready=0
    for _ in $(seq 1 50); do
        if dbus-send --session --dest=org.freedesktop.DBus --type=method_call --print-reply \
            /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>/dev/null | grep -q "org.xfce.Terminal"; then
            dbus_ready=1
            break
        fi
        sleep 0.2
    done
    [ "${dbus_ready}" -eq 1 ] || { echo "ordinary xfce4-terminal did not claim D-Bus name" >&2; exit 1; }
    exec_line="$(sed -n "s/^Exec=//p" /etc/scidesktop/eessi-apps.d/eessi-r.desktop | head -n 1)"
    case "${exec_line}" in
        *--disable-server*) ;;
        *) echo "missing --disable-server in ${exec_line}" >&2; exit 1 ;;
    esac
    eessi-launch R xfce4-terminal --disable-server -x sh -c "R --version | head -n 1 > \"${out_file}\"" >/dev/null 2>&1 &
    for _ in $(seq 1 60); do
        [ -s "${out_file}" ] && break
        sleep 0.5
    done
    cat "${out_file}"
')"
if grep -q '^R version ' <<<"${term_out}"; then
    pass "eessi-launch xfce4-terminal --disable-server keeps EESSI R with existing terminal open (${term_out})"
else
    fail "eessi-launch xfce4-terminal --disable-server keeps EESSI R with existing terminal open"
    printf '%s\n' "${term_out}" | tail -n 10 | sed 's/^/        /'
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

finish
