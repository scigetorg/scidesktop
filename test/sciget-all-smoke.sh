#!/bin/bash
# End-to-end check of an image that uses sciget-all (all sciget domains).
# Domain images that narrow /etc/sciget/catalogs.json via sciget-<domain>
# are checked by their own test/sciget-<domain>-smoke.sh instead.
#
#   ./test/sciget-all-smoke.sh [image]

set -uo pipefail

IMAGE="${1:-scidesktop}"
NAME="sciget-all-smoke-$$"
TOKEN="sciget-all-smoke"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

# Skip when a domain-specific catalog component narrows /etc/sciget/catalogs.json.
manifests="$(docker run --rm --entrypoint ls "${IMAGE}" /opt/scidesktop/manifest.d 2>/dev/null || true)"
if grep -qE '^sciget-(neuroimaging|microscopy)\.json$' <<<"${manifests}"; then
    echo "sciget-all smoke: ${IMAGE} (narrowed by a domain catalog; checked by its own smoke test)"
    exit 0
fi

cleanup() { docker rm -f "${NAME}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

as_user() { docker exec -u jovyan -w /tmp "${NAME}" bash "${2:--lc}" "$1" 2>/dev/null; }

echo "sciget-all smoke: ${IMAGE}"
docker run -d --name "${NAME}" -e JUPYTER_TOKEN="${TOKEN}" "${IMAGE}" >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }
for _ in $(seq 1 120); do
    docker exec "${NAME}" curl -fsS -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null && break
    sleep 1
done

listed="$(as_user 'sciget catalog list' | cut -f 1-3)"
[ "${listed}" = "$(printf 'neuroimaging\t1\tsystem\nmicroscopy\t2\tsystem')" ] \
    && as_user '[ ! -e ~/.config/sciget/catalogs.json ]' \
    && pass "both neuroimaging and microscopy catalogs come from the system layer" \
    || fail "both neuroimaging and microscopy catalogs come from the system layer (got: ${listed})"

for catalog in neuroimaging microscopy; do
    as_user "for _ in \$(seq 1 60); do ls ~/.cache/sciget/catalogs/${catalog}-*/ >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1" \
        && pass "the ${catalog} catalog is downloaded at start" \
        || fail "the ${catalog} catalog is downloaded at start"
done

found_neuro="$(as_user 'sciget find niimath' | awk -F '\t' 'index($1, "niimath/") == 1 && $2 == "neuroimaging"' | head -n 1)"
[ -n "${found_neuro}" ] && pass "sciget offers niimath ($(cut -f 1 <<<"${found_neuro}"))" \
    || fail "sciget offers niimath"
found_micro="$(as_user 'sciget find nextpyp' | awk -F '\t' 'index($1, "nextpyp/") == 1 && $2 == "microscopy"' | head -n 1)"
[ -n "${found_micro}" ] && pass "sciget offers nextpyp ($(cut -f 1 <<<"${found_micro}"))" \
    || fail "sciget offers nextpyp"

mp="$(as_user 'echo "${MODULEPATH:-}"')"
case ":${mp}:" in
    *:/home/jovyan/.local/share/sciget/modules/neuroimaging:*) neuro_mp=1 ;; *) neuro_mp=0 ;;
esac
case ":${mp}:" in
    *:/home/jovyan/.local/share/sciget/modules/microscopy:*) micro_mp=1 ;; *) micro_mp=0 ;;
esac
[ "${neuro_mp}" = 1 ] && [ "${micro_mp}" = 1 ] \
    && pass "Lmod MODULEPATH includes both neuroimaging and microscopy sciget module dirs" \
    || fail "Lmod MODULEPATH includes both neuroimaging and microscopy sciget module dirs (got: ${mp})"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "sciget-all smoke: all checks passed"
else
    echo "sciget-all smoke: ${FAILED} check(s) failed"
fi
exit "${FAILED}"
