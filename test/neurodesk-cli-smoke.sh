#!/bin/bash
# End-to-end check of an image that copies the neurodesk-cli component.
#
#   ./test/neurodesk-cli-smoke.sh [image]
#
# Runs what a terminal runs: a login shell of the notebook user in a started
# session, with the session's Slurm queue up.

set -uo pipefail

IMAGE="${1:-neurodesktop}"
NAME="neurodesk-cli-smoke-$$"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() { docker rm -f "${NAME}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

terminal() { docker exec -u jovyan -w /tmp "${NAME}" bash -lc "$1" 2>&1; }

echo "neurodesk-cli smoke: ${IMAGE}"
docker run -d --name "${NAME}" --cpus=2 --memory=2g -e JUPYTER_TOKEN=neurodesk-cli-smoke "${IMAGE}" >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }
for _ in $(seq 1 120); do
    docker exec "${NAME}" curl -fsS -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null && break
    sleep 1
done
terminal '/opt/slurm/bin/slurm-session wait' >/dev/null

help="$(terminal 'neurodesk --help')"
grep -q '^usage: neurodesk <command>' <<<"${help}" && grep -q '^  cite ' <<<"${help}" && grep -q '^  kernel ' <<<"${help}" \
    && pass "neurodesk --help lists the commands" || fail "neurodesk --help lists the commands"
[ "$(terminal 'neurodesk check slurm')" = "[PASS] slurm  partitions: scidesktop*" ] \
    && pass "neurodesk check slurm finds the session's queue" \
    || fail "neurodesk check slurm finds the session's queue (got: $(terminal 'neurodesk check slurm'))"
[ "$(terminal 'neurodesk check gpu')" = "[SKIP] gpu    no NVIDIA GPU visible in this container" ] \
    && pass "neurodesk check gpu skips without a GPU" || fail "neurodesk check gpu skips without a GPU"
info="$(terminal 'neurodesk info')"
grep -q '^Image: .*neurodesk-cli.*slurm' <<<"${info}" && grep -qE '^CPUs: +2$' <<<"${info}" \
    && grep -qE '^Memory: +2\.0 GiB$' <<<"${info}" \
    && pass "neurodesk info shows the components and the container's 2 CPUs and 2 GiB" \
    || { fail "neurodesk info shows the components and the container's 2 CPUs and 2 GiB"; printf '%s\n' "${info}" | sed 's/^/        /'; }
[ "$(terminal 'neurodesk kernel list')" = "No container kernels registered. Add one with: neurodesk-kernel add <module>" ] \
    && pass "neurodesk kernel list answers" || fail "neurodesk kernel list answers"

# A module loaded in a terminal is recorded, and neurodesk cite reads the
# record. The catalogue is a local file: this check needs no network.
out="$(terminal '
    modules="${HOME}/.local/share/sciget/modules/neuroimaging/smoketool"
    mkdir -p "${modules}" && echo "whatis(\"smoke\")" > "${modules}/1.2.lua"
    echo "package=${LMOD_PACKAGE_PATH:-}"
    module use "${HOME}/.local/share/sciget/modules/neuroimaging" && module load smoketool/1.2
    cut -f 1,2 "${HOME}/.local/state/neurodesk/module-usage.tsv" | tr "\t" "/"
    echo "{\"smoketool\": {\"apps\": {\"smoketool 1.2\": {\"version\": \"20260101\", \"exec\": \"\", \"image\": \"smoketool_1.2\"}}, \"categories\": [\"programming\"], \"citation\": \"Smoke, A. (2026). https://doi.org/10.0000/smoke\"}}" > /tmp/apps.json
    NEURODESKTOP_CITE_CATALOGUE_URL=file:///tmp/apps.json neurodesk cite >/dev/null && grep -c "doi.org/10.0000/smoke" "${HOME}/CITATIONS.md"')"
[ "${out}" = "$(printf 'package=/opt/neurodesk-cli/lmod\nsmoketool/1.2\n1')" ] \
    && pass "a loaded module is recorded and neurodesk cite writes its citation" \
    || { fail "a loaded module is recorded and neurodesk cite writes its citation"; printf '%s\n' "${out}" | sed 's/^/        /'; }

echo
echo "  NOT TESTED: neurodesk kernel add WITH A REAL TOOL CONTAINER. THAT NEEDS THE"
echo "  NEURODESK CVMFS REPOSITORY AND A CONTAINER WITH ipykernel. The command's"
echo "  refusal of a module that is not a container's is checked by the component's test."
echo
if [ "${FAILED}" -eq 0 ]; then
    echo "neurodesk-cli smoke: all checks passed"
else
    echo "neurodesk-cli smoke: ${FAILED} check(s) failed"
fi
exit "${FAILED}"
