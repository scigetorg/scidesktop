#!/bin/bash
# End-to-end check of an image that copies the neurodesk-compat component.
#
#   ./test/neurodesk-compat-smoke.sh [image]
#
# Verifies FreeSurfer/nf-neuro defaults, bundled nf-neuro modules,
# getting-started notebook seeding in a fresh home, and local module discovery.

set -uo pipefail

IMAGE="${1:-neurodesktop}"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

echo "neurodesk-compat smoke: ${IMAGE}"
out=$(docker run --rm "${IMAGE}" bash -lc '
    set -e
    echo "subjects_dir=${APPTAINERENV_SUBJECTS_DIR:-}"
    echo "nf_neuro=${NF_NEURO_MODULES_DIR:-}"
    test -d /opt/nf-neuro/modules/modules && echo "nf_neuro_dir=ok"
    test -f "${HOME}/getting-started.ipynb" && echo "getting_started=ok"
    tmp="$(mktemp -d)"
    mkdir -p "${tmp}/modules/demo"
    printf "#%%Module\n" > "${tmp}/modules/demo/1.0"
    found="$(NEURODESKTOP_LOCAL_CONTAINERS="${tmp}" /etc/scidesktop/modulepath.d/55-neurodesk-local)"
    [ "${found}" = "${tmp}/modules" ] && echo "local_modules=ok"
    rm -rf "${tmp}"
' 2>/dev/null)

has() { printf '%s\n' "${out}" | grep -qxF "$1"; }

has "subjects_dir=/home/jovyan/freesurfer-subjects-dir" \
    && pass "APPTAINERENV_SUBJECTS_DIR defaults into user home" \
    || fail "APPTAINERENV_SUBJECTS_DIR defaults into user home"
has "nf_neuro=/opt/nf-neuro/modules" \
    && pass "NF_NEURO_MODULES_DIR set" \
    || fail "NF_NEURO_MODULES_DIR set"
has "nf_neuro_dir=ok" \
    && pass "pinned nf-neuro modules present" \
    || fail "pinned nf-neuro modules present"
has "getting_started=ok" \
    && pass "getting-started.ipynb seeded into a fresh home" \
    || fail "getting-started.ipynb seeded into a fresh home"
has "local_modules=ok" \
    && pass "55-neurodesk-local discovers mounted local module directories" \
    || fail "55-neurodesk-local discovers mounted local module directories"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "neurodesk-compat smoke: all checks passed"
else
    echo "neurodesk-compat smoke: ${FAILED} check(s) failed; output:"
    printf '%s\n' "${out}" | sed 's/^/        /'
fi
exit "${FAILED}"
