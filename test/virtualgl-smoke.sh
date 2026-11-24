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
    set -euo pipefail
    echo "vglrun=$(command -v vglrun)"
    echo "vgl-eglinfo=$(command -v vgl-eglinfo)"
    echo "glxinfo=$(command -v glxinfo)"
    echo "nvidia_caps=${NVIDIA_DRIVER_CAPABILITIES:-}"
    test -r /usr/local/bin/before-notebook.d/13-virtualgl-env.sh && echo "env_hook=ok"
    libs="libdlfaker.so libgefaker.so libvglfaker.so libvglfaker-nodl.so"
    if [ "$(dpkg --print-architecture)" = "amd64" ]; then
        libs="${libs} libvglfaker-opencl.so"
    fi
    for lib in ${libs}; do
        test -r "/usr/lib/${lib}"
    done
    echo "faker_libs=ok"
    ldd_out="$(ldd /usr/lib/libvglfaker.so /usr/lib/libdlfaker.so /opt/VirtualGL/bin/glxspheres64 2>&1)"
    case "${ldd_out}" in
        *"not found"*) ;;
        *) echo "ldd=ok" ;;
    esac
    preload_out="$(vglrun /bin/true 2>&1)"
    case "${preload_out}" in
        *"cannot be preloaded"*|*ERROR*) ;;
        *) echo "preload=ok" ;;
    esac
' 2>/dev/null)

has() { printf '%s\n' "${out}" | grep -qxF "$1"; }

has "vglrun=/usr/local/bin/vglrun" && pass "vglrun on PATH" || fail "vglrun on PATH"
has "vgl-eglinfo=/usr/local/bin/vgl-eglinfo" && pass "vgl-eglinfo on PATH" || fail "vgl-eglinfo on PATH"
has "glxinfo=/usr/bin/glxinfo" && pass "glxinfo (mesa-utils) on PATH" || fail "glxinfo (mesa-utils) on PATH"
has "faker_libs=ok" && pass "VirtualGL faker libraries present in /usr/lib" || fail "VirtualGL faker libraries present in /usr/lib"
has "ldd=ok" && pass "VirtualGL libraries and glxspheres64 resolve all shared libs" || fail "VirtualGL libraries and glxspheres64 resolve all shared libs"
has "preload=ok" && pass "vglrun preloads libdlfaker.so and libvglfaker.so cleanly" || fail "vglrun preloads libdlfaker.so and libvglfaker.so cleanly"
has "env_hook=ok" && pass "VirtualGL EGL startup hook present" || fail "VirtualGL EGL startup hook present"
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
