#!/bin/bash
# Every end-to-end check of one image in images/.
#
#   ./test/image-smoke.sh <image> [ref]
#
# <image> is a folder in images/; [ref] is the built image to check
# (default: <image>, as `docker buildx bake` tags it).
#
#   1. The image holds the components its bake target names and nothing of
#      any other component (test/contract.py image).
#   2. Base-integrity checks:
#      - test/smoke.sh on the base image and any domain image whose added
#        components touch startup hooks, shell profiles, home defaults,
#        modulepath, CVMFS, or desktop menus (test/contract.py surfaces -> full).
#      - test/flavour-smoke.sh on domain images whose added components only add
#        kernels, catalogs, Jupyter config parts, or VS Code extensions
#        (test/contract.py surfaces -> flavour). Set SMOKE_FULL_BASE=1 to force
#        test/smoke.sh on every image.
#      - test/notebook-and-sciget-smoke.sh (whose catalog differs per image)
#        and test/hpc-smoke.sh (foreign-UID startup & loopback-only check) run
#        on every image.
#   3. The checks of each component the image adds to the image it is FROM
#      (test/contract.py added): test/<component>-smoke.sh. A component is
#      tested once, in the first image that holds it; the images built FROM
#      that one hold the same layer. SMOKE_ALL_COMPONENTS=1 tests every
#      component the image holds instead. When ai-ready is in the list,
#      test/ai-ready-smoke.sh overlaps with the other checks by default
#      (set SMOKE_PARALLEL_AI_READY=0 to run it sequentially).
#   4. The image's own checks, images/<image>/smoke.sh, when it has them.
#
# A domain image lists nothing here: copying a component brings its checks.

set -uo pipefail

image="${1:?usage: image-smoke.sh <image> [ref]}"
ref="${2:-${image}}"
here="$(dirname "$0")"
failed=0

run() {
    echo "--- $*"
    "$@" || failed=1
}

ai_ready_pid=""
ai_ready_log=""
cleanup() {
    if [ -n "${ai_ready_pid}" ]; then
        kill "${ai_ready_pid}" 2>/dev/null || true
        wait "${ai_ready_pid}" 2>/dev/null || true
    fi
    if [ -n "${ai_ready_log}" ]; then
        rm -f "${ai_ready_log}"
    fi
}
trap cleanup EXIT

run python3 "${here}/contract.py" image "${image}" "${ref}"
surface="$(python3 "${here}/contract.py" surfaces "${image}")" \
    || { echo "  FAIL  cannot determine test surface of ${image}"; exit 1; }
if [ "${SMOKE_ALL_COMPONENTS:-0}" = 1 ]; then
    components="$(docker run --rm --entrypoint ls "${ref}" /opt/scidesktop/manifest.d | sed 's/\.json$//')" \
        || { echo "  FAIL  cannot list the components of ${ref}"; exit 1; }
else
    components="$(python3 "${here}/contract.py" added "${image}")" \
        || { echo "  FAIL  cannot list the components ${image} adds"; exit 1; }
fi

# ai-ready-smoke.sh runs ~7 min (bounded at --cpus=2 --memory=4g on its own
# host port). Overlap it with the rest of this image's smoke checks so it
# does not sit on top of them on the critical path.
if [ "${SMOKE_PARALLEL_AI_READY:-1}" = 1 ] \
    && grep -qx 'ai-ready' <<<"${components}" \
    && [ -x "${here}/ai-ready-smoke.sh" ]; then
    ai_ready_log="$(mktemp)"
    "${here}/ai-ready-smoke.sh" "${ref}" >"${ai_ready_log}" 2>&1 &
    ai_ready_pid=$!
fi

if [ "${SMOKE_FULL_BASE:-0}" = 1 ] || [ "${surface}" = full ]; then
    run "${here}/smoke.sh" "${ref}"
else
    run "${here}/flavour-smoke.sh" "${ref}"
fi
run "${here}/notebook-and-sciget-smoke.sh" "${ref}"
run "${here}/hpc-smoke.sh" "${ref}"

for component in ${components}; do
    if [ "${component}" = "ai-ready" ] && [ -n "${ai_ready_pid}" ]; then
        continue
    fi
    smoke="${here}/${component}-smoke.sh"
    if [ -x "${smoke}" ]; then
        run "${smoke}" "${ref}"
    fi
done
if [ -x "${here}/../images/${image}/smoke.sh" ]; then
    run "${here}/../images/${image}/smoke.sh" "${ref}"
fi
if [ -n "${ai_ready_pid}" ]; then
    echo "--- ${here}/ai-ready-smoke.sh ${ref}"
    ai_rc=0
    wait "${ai_ready_pid}" || ai_rc=$?
    ai_ready_pid=""
    cat "${ai_ready_log}"
    rm -f "${ai_ready_log}"
    ai_ready_log=""
    if [ "${ai_rc}" -ne 0 ]; then
        failed=1
    fi
fi

echo
if [ "${failed}" -eq 0 ]; then
    echo "image smoke: ${ref} passed"
else
    echo "image smoke: ${ref} FAILED"
fi
exit "${failed}"
