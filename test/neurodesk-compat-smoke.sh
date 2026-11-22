#!/bin/bash
# End-to-end check of an image that copies the neurodesk-compat component.
#
#   ./test/neurodesk-compat-smoke.sh [image]
#
# Verifies:
#   - FreeSurfer/nf-neuro defaults across login, non-login, and root-started
#     NB_USER-renamed sessions
#   - Bundled nf-neuro modules and getting-started.ipynb seeding
#   - Real `module load` precedence (55-neurodesk-local beats 60-neurodesk-cvmfs
#     even when CVMFS was already in MODULEPATH) and SitePackage.lua logging
#   - /neurodesktop-storage auto-bind and explicit empty APPTAINER_BINDPATH opt-out

set -uo pipefail

IMAGE="${1:-neurodesktop}"
FAILED=0
TMP_HOST="$(mktemp -d)"

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() {
    rm -rf "${TMP_HOST}"
}
trap cleanup EXIT

mkdir -p "${TMP_HOST}/cvmfs/duptool" "${TMP_HOST}/local/modules/duptool"
printf 'setenv("DUPTOOL_SRC", "cvmfs")\n' > "${TMP_HOST}/cvmfs/duptool/1.0.lua"
printf 'setenv("DUPTOOL_SRC", "local")\n' > "${TMP_HOST}/local/modules/duptool/1.0.lua"
chmod -R a+rX "${TMP_HOST}"

echo "neurodesk-compat smoke: ${IMAGE}"
out=$(docker run --rm \
    -v "${TMP_HOST}/cvmfs:/cvmfs/neurodesk.ardc.edu.au/neurodesk-modules/demo:ro" \
    -v "${TMP_HOST}/local:/neurodesktop-storage/containers:ro" \
    -e "MODULEPATH=/cvmfs/neurodesk.ardc.edu.au/neurodesk-modules/demo" \
    "${IMAGE}" bash -lc '
    set -euo pipefail
    echo "subjects_dir=${APPTAINERENV_SUBJECTS_DIR:-}"
    echo "nf_neuro=${NF_NEURO_MODULES_DIR:-}"
    echo "bindpath=${APPTAINER_BINDPATH:-unset}"
    test -d /opt/nf-neuro/modules/modules && echo "nf_neuro_dir=ok"
    test -f "${HOME}/getting-started.ipynb" && echo "getting_started=ok"
    module load duptool/1.0 >/dev/null 2>&1
    [ "${DUPTOOL_SRC:-}" = "local" ] && echo "local_precedence=ok"
    grep -q "^duptool	1.0	" "${HOME}/.local/state/scigethelpers/module-usage.tsv" && echo "local_citation=ok"
' 2>/dev/null)

# Also verify Jupyter's startup hook (35-lmod-modulepath.sh) places local
# modules ahead of CVMFS when CVMFS was already in MODULEPATH (without login shell).
startup_mp="$(docker run --rm \
    -v "${TMP_HOST}/cvmfs:/cvmfs/neurodesk.ardc.edu.au/neurodesk-modules/demo:ro" \
    -v "${TMP_HOST}/local:/neurodesktop-storage/containers:ro" \
    -e "MODULEPATH=/cvmfs/neurodesk.ardc.edu.au/neurodesk-modules/demo" \
    "${IMAGE}" bash -c '
    echo "startup_mp=${MODULEPATH:-}"
' 2>/dev/null || true)"
printf '%s\n' "${startup_mp}" | grep -q '^startup_mp=.*\/neurodesktop-storage\/containers\/modules:.*\/cvmfs\/neurodesk\.ardc\.edu\.au\/neurodesk-modules\/demo' \
    && pass "Jupyter startup hook (35-lmod-modulepath.sh) puts local modules ahead of CVMFS" \
    || fail "Jupyter startup hook (35-lmod-modulepath.sh) puts local modules ahead of CVMFS"

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
has "local_precedence=ok" \
    && pass "local Neurodesk modules beat CVMFS duplicates in real module load" \
    || fail "local Neurodesk modules beat CVMFS duplicates in real module load"
has "local_citation=ok" \
    && pass "SitePackage.lua logs legacy local module loads for scigethelpers cite" \
    || fail "SitePackage.lua logs legacy local module loads for scigethelpers cite"
printf '%s\n' "${out}" | grep -q '^bindpath=.*\/neurodesktop-storage' \
    && pass "/neurodesktop-storage auto-binds when mounted" \
    || fail "/neurodesktop-storage auto-binds when mounted"

# Root-started session with renamed NB_USER resolves APPTAINERENV_SUBJECTS_DIR
# and MPLCONFIGDIR to the renamed user's home, and leaves APPTAINER_BINDPATH
# unset when no host storage mounts exist.
root_out="$(docker run --rm --user root -e NB_USER=alice "${IMAGE}" bash -c '
    echo "subj=${APPTAINERENV_SUBJECTS_DIR:-}"
    echo "mpl=${MPLCONFIGDIR:-}"
    echo "bind=${APPTAINER_BINDPATH:-unset}"
' 2>/dev/null || true)"
printf '%s\n' "${root_out}" | grep -qxF 'subj=/home/alice/freesurfer-subjects-dir' \
    && pass "root-started NB_USER=alice gets /home/alice/freesurfer-subjects-dir" \
    || fail "root-started NB_USER=alice gets /home/alice/freesurfer-subjects-dir"
printf '%s\n' "${root_out}" | grep -qxF 'mpl=/home/alice/.config/matplotlib-mpldir' \
    && pass "root-started NB_USER=alice gets /home/alice/.config/matplotlib-mpldir" \
    || fail "root-started NB_USER=alice gets /home/alice/.config/matplotlib-mpldir"
printf '%s\n' "${root_out}" | grep -qxF 'bind=unset' \
    && pass "APPTAINER_BINDPATH stays unset when no host storage dirs are mounted" \
    || fail "APPTAINER_BINDPATH stays unset when no host storage dirs are mounted"

optout="$(docker run --rm \
    -v "${TMP_HOST}/local:/neurodesktop-storage/containers:ro" \
    -e APPTAINER_BINDPATH="" "${IMAGE}" bash -c 'echo "optout=${APPTAINER_BINDPATH+set}:${APPTAINER_BINDPATH}"' 2>/dev/null || true)"
printf '%s\n' "${optout}" | grep -qxF 'optout=set:' \
    && pass "empty APPTAINER_BINDPATH=\"\" opt-out is preserved even when storage is mounted" \
    || fail "empty APPTAINER_BINDPATH=\"\" opt-out is preserved"

override="$(docker run --rm \
    -v "${TMP_HOST}/local:/neurodesktop-storage/containers:ro" \
    -e APPTAINER_BINDPATH="/tmp:ro" "${IMAGE}" bash -c 'echo "override=${APPTAINER_BINDPATH:-}"' 2>/dev/null || true)"
printf '%s\n' "${override}" | grep -qxF 'override=/tmp:ro' \
    && pass "explicit non-empty APPTAINER_BINDPATH override is preserved verbatim" \
    || fail "explicit non-empty APPTAINER_BINDPATH override is preserved verbatim"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "neurodesk-compat smoke: all checks passed"
else
    echo "neurodesk-compat smoke: ${FAILED} check(s) failed; output:"
    printf '%s\n' "${out}" | sed 's/^/        /'
fi
exit "${FAILED}"
