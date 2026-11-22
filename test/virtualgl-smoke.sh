#!/bin/bash
# End-to-end check of an image that copies the virtualgl component.
#
#   ./test/virtualgl-smoke.sh [image]

set -uo pipefail

IMAGE="${1:-scidesktop}"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

echo "virtualgl smoke: ${IMAGE}"
out=$(docker run --rm "${IMAGE}" bash -lc '
    echo "vglrun=$(command -v vglrun)"
    echo "vgl-eglinfo=$(command -v vgl-eglinfo)"
    echo "glxinfo=$(command -v glxinfo)"
    echo "nvidia_caps=${NVIDIA_DRIVER_CAPABILITIES:-}"
    /opt/VirtualGL/bin/vglrun -h 2>&1 | grep -qi "virtualgl\|vglrun" && echo "vglrun_help=ok"
' 2>/dev/null)

has() { printf '%s\n' "${out}" | grep -qxF "$1"; }

has "vglrun=/usr/local/bin/vglrun" && pass "vglrun on PATH" || fail "vglrun on PATH"
has "vgl-eglinfo=/usr/local/bin/vgl-eglinfo" && pass "vgl-eglinfo on PATH" || fail "vgl-eglinfo on PATH"
has "glxinfo=/usr/bin/glxinfo" && pass "glxinfo (mesa-utils) on PATH" || fail "glxinfo (mesa-utils) on PATH"
has "vglrun_help=ok" && pass "vglrun runs" || fail "vglrun runs"
printf '%s\n' "${out}" | grep -q '^nvidia_caps=.*graphics' \
    && pass "NVIDIA_DRIVER_CAPABILITIES exposes graphics" \
    || fail "NVIDIA_DRIVER_CAPABILITIES exposes graphics"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "virtualgl smoke: all checks passed"
else
    echo "virtualgl smoke: ${FAILED} check(s) failed"
    printf '%s\n' "${out}" | sed 's/^/        /'
fi
exit "${FAILED}"
