#!/bin/bash
# End-to-end check of an image that copies a sciget catalog component.
# Called by test/sciget-<catalog>-smoke.sh.
#
#   ./test/sciget-catalog-check.sh <image> <catalog> <offered tool> [tool of another catalog]
#
# Runs what a user runs: sciget as the notebook user in a started session.
# The catalog is downloaded from its publisher, as in every session.

set -uo pipefail

IMAGE="${1:?usage: sciget-catalog-check.sh <image> <catalog> <offered tool> [tool of another catalog]}"
CATALOG="${2:?}"
OFFERED="${3:?}"
OTHER="${4:-}"
NAME="sciget-${CATALOG}-smoke-$$"
TOKEN="sciget-smoke"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() {
    docker rm -f "${NAME}" "${NAME}-cvmfs" >/dev/null 2>&1 || true
    [ -z "${MOCK_CVMFS:-}" ] || rm -rf "${MOCK_CVMFS:?}"
}
trap cleanup EXIT

as_user() { docker exec -u jovyan -w /tmp "${NAME}" bash "${2:--lc}" "$1" 2>/dev/null; }

echo "sciget-${CATALOG} smoke: ${IMAGE}"
docker run -d --name "${NAME}" -e JUPYTER_TOKEN="${TOKEN}" "${IMAGE}" >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }
for _ in $(seq 1 120); do
    docker exec "${NAME}" curl -fsS -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null && break
    sleep 1
done

# The user sees the image's catalog, and only it, from sciget's system layer:
# nothing is copied into the home.
listed="$(as_user 'sciget catalog list' | cut -f 1-3)"
[ "${listed}" = "$(printf '%s\t1\tsystem' "${CATALOG}")" ] && as_user '[ ! -e ~/.config/sciget/catalogs.json ]' \
    && pass "the ${CATALOG} catalog, and no other, comes from the system layer" \
    || fail "the ${CATALOG} catalog, and no other, comes from the system layer (got: ${listed})"
as_user "for _ in \$(seq 1 60); do ls ~/.cache/sciget/catalogs/${CATALOG}-*/ >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1" \
    && pass "the catalog is downloaded at start" \
    || fail "the catalog is downloaded at start (see ~/.cache/sciget/refresh.log)"

# What the image offers, and what it does not: a tool of the catalog is
# found, and every tool sciget offers comes strictly from that catalog.
found="$(as_user "sciget find ${OFFERED}" | awk -F '\t' -v tool="${OFFERED}" -v catalog="${CATALOG}" \
    'index($1, tool "/") == 1 && $2 == catalog' | head -n 1)"
[ -n "${found}" ] && pass "sciget offers ${OFFERED} ($(cut -f 1 <<<"${found}"))" \
    || fail "sciget offers ${OFFERED}"
if ! all_tools="$(as_user 'sciget find')"; then
    fail "sciget find failed while checking catalog isolation"
elif [ -z "${all_tools}" ]; then
    fail "sciget find returned no tools"
else
    total="$(awk -F '\t' -v catalog="${CATALOG}" '$2 != "" && $2 != catalog' <<<"${all_tools}" | wc -l)"
    if [ -n "${OTHER}" ]; then
        other="$(awk -F '\t' -v tool="${OTHER}" 'index($1, tool "/") == 1' <<<"${all_tools}" | wc -l)"
        [ "${other}" = 0 ] && [ "${total}" = 0 ] && pass "sciget offers no ${OTHER} and nothing outside ${CATALOG}" \
            || fail "sciget offers no ${OTHER} and nothing outside ${CATALOG} (${other} ${OTHER}, ${total} from other catalogs)"
    else
        [ "${total}" = 0 ] && pass "sciget offers nothing outside ${CATALOG}" \
            || fail "sciget offers nothing outside ${CATALOG} (${total} from other catalogs)"
    fi
fi

# Modules sciget installs are on the path: in new login shells (JupyterLab
# terminals) and other interactive shells (desktop terminals), and for the
# Jupyter server's Lmod panel, which lists the folders it started with.
as_user "d=\"\$(sciget config get module_dir)/${CATALOG}/smoketool\"; mkdir -p \"\${d}\" && echo 'whatis(\"smoke\")' >\"\${d}/1.0.lua\""
for mode in -lc -ic; do
    docker exec -u jovyan -w /tmp "${NAME}" bash "${mode}" 'module -t avail smoketool' >"/tmp/${NAME}.modules" 2>&1
    grep -q '^smoketool/1.0' "/tmp/${NAME}.modules" \
        && pass "sciget modules on the path (bash ${mode})" \
        || fail "sciget modules on the path (bash ${mode})"
done
rm -f "/tmp/${NAME}.modules"
paths="$(docker exec "${NAME}" curl -s -H "Authorization: token ${TOKEN}" "http://127.0.0.1:8888/module/paths" 2>/dev/null)"
grep -q "sciget/modules/${CATALOG}" <<<"${paths}" \
    && pass "sciget modules on the Jupyter server's path" \
    || fail "sciget modules on the Jupyter server's path"

# Narrowed non-neuroimaging catalogs must not expose all of Neurodesk's CVMFS
# neurodesk-modules/* tree; instead Lmod sees only the catalog's own CVMFS tools.
if [ "${CATALOG}" != "neuroimaging" ]; then
    MOCK_CVMFS="$(mktemp -d)"
    sample_entry="$(as_user "sciget find" | awk -F '\t' -v cat="${CATALOG}" '
        $2 == cat && index($1, "/") > 1 {
            i = index($1, "/")
            print substr($1, 1, i - 1) "\t" substr($1, i + 1)
            exit
        }')"
    sample_tool="${sample_entry%%$'\t'*}"
    sample_ver="${sample_entry#*$'\t'}"
    if [ -z "${sample_tool}" ] || [ -z "${sample_ver}" ] || [ "${sample_tool}" = "${sample_entry}" ]; then
        fail "could not pick a ${CATALOG} sample tool for CVMFS Lmod isolation check"
    else
        mkdir -p \
            "${MOCK_CVMFS}/neurodesk-modules/functional_imaging/afni" \
            "${MOCK_CVMFS}/containers/modules/afni" \
            "${MOCK_CVMFS}/containers/modules/${sample_tool}"
        printf 'whatis("afni")\n' > "${MOCK_CVMFS}/neurodesk-modules/functional_imaging/afni/26.0.lua"
        printf 'whatis("afni")\n' > "${MOCK_CVMFS}/containers/modules/afni/26.0.lua"
        printf 'whatis("%s")\nsetenv("SCIDESKTOP_CVMFS_MOD_LOADED", "1")\n' "${sample_tool}" \
            > "${MOCK_CVMFS}/containers/modules/${sample_tool}/${sample_ver}.lua"
        chmod -R a+rX "${MOCK_CVMFS}"
        cvmfs_name="${NAME}-cvmfs"
        docker run -d --name "${cvmfs_name}" -e JUPYTER_TOKEN="${TOKEN}" \
            -e SCIDESKTOP_SCIGET_REFRESH=no \
            -v "${MOCK_CVMFS}:/cvmfs/neurodesk.ardc.edu.au:ro" "${IMAGE}" >/dev/null
        for _ in $(seq 1 120); do
            docker exec "${cvmfs_name}" curl -fsS -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null && break
            sleep 1
        done
        # Prime jupyterlmod's avail cache before the catalog exists, then run a
        # manual `sciget refresh` and confirm the running panel picks up the new
        # CVMFS modules without restarting Jupyter.
        docker exec "${cvmfs_name}" curl -fsS -o /dev/null -H "Authorization: token ${TOKEN}" \
            "http://127.0.0.1:8888/module/modules" 2>/dev/null || true
        docker exec -u jovyan "${cvmfs_name}" bash -lc 'sciget refresh >/dev/null' 2>/dev/null || true
        lmod_modules="$(docker exec "${cvmfs_name}" curl -s -H "Authorization: token ${TOKEN}" "http://127.0.0.1:8888/module/modules" 2>/dev/null)"
        if grep -q "\"${sample_tool}/${sample_ver}\"" <<<"${lmod_modules}" && ! grep -q '"afni/' <<<"${lmod_modules}"; then
            pass "Jupyter Lmod shows ${CATALOG} CVMFS module (${sample_tool}/${sample_ver}) and excludes afni"
        else
            fail "Jupyter Lmod shows ${CATALOG} CVMFS module (${sample_tool}/${sample_ver}) and excludes afni (got: ${lmod_modules:0:200})"
        fi
        if docker exec -u jovyan -w /tmp "${cvmfs_name}" bash -lc \
            "module load '${sample_tool}/${sample_ver}' && [ \"\${SCIDESKTOP_CVMFS_MOD_LOADED:-}\" = 1 ]" >/dev/null 2>&1; then
            pass "symlinked ${CATALOG} CVMFS module (${sample_tool}/${sample_ver}) loads via Lmod"
        else
            fail "symlinked ${CATALOG} CVMFS module (${sample_tool}/${sample_ver}) loads via Lmod"
        fi
        docker rm -f "${cvmfs_name}" >/dev/null 2>&1 || true
    fi
    rm -rf "${MOCK_CVMFS}"
    MOCK_CVMFS=""
fi

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "sciget-${CATALOG} smoke: all checks passed"
else
    echo "sciget-${CATALOG} smoke: ${FAILED} check(s) failed"
fi
exit "${FAILED}"
