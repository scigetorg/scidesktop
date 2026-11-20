#!/bin/bash
# End-to-end check of an image that copies the datalad component.
#
#   ./test/datalad-smoke.sh [image]
#
# Runs what a terminal runs: a login shell of the notebook user in the
# assembled image, where the Jupyter environment's Python is first on PATH.
# No network.

set -uo pipefail

IMAGE="${1:-neurodesktop}"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

echo "datalad smoke: ${IMAGE}"
out=$(docker run --rm "${IMAGE}" bash -lc '
    cd "$(mktemp -d)"
    git config --global user.name "scidesktop smoke"
    git config --global user.email "smoke@scidesktop.invalid"
    echo "datalad=$(datalad --version) at $(readlink -f "$(command -v datalad)")"
    echo "git-annex=$(git annex version --raw) at $(readlink -f "$(command -v git-annex)")"
    echo "python=$(command -v python)"
    datalad create origin >/dev/null 2>&1 && head -c 4096 /dev/urandom > origin/data.bin \
        && datalad save -d origin -m data >/dev/null 2>&1 && [ -L origin/data.bin ] \
        && datalad clone origin clone >/dev/null 2>&1 && [ ! -e clone/data.bin ] \
        && datalad get -d clone clone/data.bin >/dev/null 2>&1 && cmp -s origin/data.bin clone/data.bin \
        && echo "roundtrip=ok"
    cat /opt/scidesktop/manifest.d/datalad.json' 2>/dev/null)

version() { printf '%s\n' "${out}" | sed -n "s/.*\"$1\": \"\([^\"]*\)\".*/\1/p"; }
has() { printf '%s\n' "${out}" | grep -qxF "$1"; }

has "datalad=datalad $(version datalad) at /opt/datalad/bin/datalad" \
    && pass "datalad $(version datalad) runs" || fail "datalad runs"
printf '%s\n' "${out}" | grep -q "^git-annex=$(version git-annex)-g[0-9a-f]* at /opt/datalad/bin/git-annex$" \
    && pass "git-annex $(version git-annex) runs" || fail "git-annex runs"
has "python=/opt/conda/bin/python" \
    && pass "the session's Python is still the Jupyter environment's" \
    || fail "the session's Python is still the Jupyter environment's"
has "roundtrip=ok" && pass "a file is annexed, cloned and fetched back" \
    || fail "a file is annexed, cloned and fetched back"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "datalad smoke: all checks passed"
else
    echo "datalad smoke: ${FAILED} check(s) failed; the session printed:"
    printf '%s\n' "${out}" | sed 's/^/        /'
fi
exit "${FAILED}"
