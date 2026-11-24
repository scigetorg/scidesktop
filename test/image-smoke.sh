#!/bin/bash
# Every end-to-end check of one image in images/, in the order CI runs them.
#
#   ./test/image-smoke.sh <image> [ref]
#
# <image> is a folder in images/; [ref] is the built image to check
# (default: <image>, as `docker buildx bake` tags it).
#
#   1. The image holds the components its bake target names and nothing of
#      any other component (test/contract.py image).
#   2. The base's checks, which every image must still pass (test/smoke.sh)
#      and its notebook and sciget checks, whose catalog differs per image.
#   3. The checks of each component the image adds to the image it is FROM
#      (test/contract.py added): test/<component>-smoke.sh. A component is
#      tested once, in the first image that holds it; the images built FROM
#      that one hold the same layer. The base also runs the session's Slurm
#      checks (test/hpc-smoke.sh). SMOKE_ALL_COMPONENTS=1 tests every
#      component the image holds instead.
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

run python3 "${here}/contract.py" image "${image}" "${ref}"
run "${here}/smoke.sh" "${ref}"
run "${here}/notebook-and-sciget-smoke.sh" "${ref}"
if [ "${SMOKE_ALL_COMPONENTS:-0}" = 1 ]; then
    components="$(docker run --rm --entrypoint ls "${ref}" /opt/scidesktop/manifest.d | sed 's/\.json$//')" \
        || { echo "  FAIL  cannot list the components of ${ref}"; exit 1; }
else
    components="$(python3 "${here}/contract.py" added "${image}")" \
        || { echo "  FAIL  cannot list the components ${image} adds"; exit 1; }
fi
if [ "${SMOKE_ALL_COMPONENTS:-0}" = 1 ] || grep -qx slurm <<<"${components}"; then
    run "${here}/hpc-smoke.sh" "${ref}"
fi
for component in ${components}; do
    smoke="${here}/${component}-smoke.sh"
    if [ -x "${smoke}" ]; then
        run "${smoke}" "${ref}"
    fi
done
if [ -x "${here}/../images/${image}/smoke.sh" ]; then
    run "${here}/../images/${image}/smoke.sh" "${ref}"
fi

echo
if [ "${failed}" -eq 0 ]; then
    echo "image smoke: ${ref} passed"
else
    echo "image smoke: ${ref} FAILED"
fi
exit "${failed}"
