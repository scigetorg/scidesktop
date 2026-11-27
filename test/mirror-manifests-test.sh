#!/bin/bash
# Checks .github/scripts/mirror-manifests against local source and destination
# registries: multi-arch preservation, rolling-tag safety when main advances
# (in pass 1, between date and latest, across images, and during tag retry
# backoff), retry on Quay read-only maintenance, and fail-fast on auth errors.
#
#   test/mirror-manifests-test.sh
#
# Needs Docker with buildx, git and curl (or crane on PATH). Removes what it
# starts.
set -euo pipefail
cd "$(dirname "$0")/.."
script="$(pwd)/.github/scripts/mirror-manifests"
installer="$(pwd)/.github/scripts/install-crane"
arches="$(components/target-arch list)"
name="mirror-manifests-test-$$"
work="$(mktemp -d)"
cleanup() {
    docker rm --force --volumes "${name}-src" "${name}-dst" >/dev/null 2>&1 || true
    docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -F "${name}" | xargs --no-run-if-empty docker image rm >/dev/null 2>&1 || true
    rm -rf "${work}"
}
trap cleanup EXIT

if command -v crane >/dev/null 2>&1; then
    real_crane="$(command -v crane)"
else
    "${installer}" "${work}/crane-bin" >/dev/null
    real_crane="${work}/crane-bin/crane"
fi

start_registry() {
    local container="$1" addr
    docker run --detach --name "${container}" --publish 127.0.0.1::5000 registry:2 >/dev/null
    addr="$(docker port "${container}" 5000/tcp | head -n 1)"
    addr="localhost:${addr##*:}"
    for _ in $(seq 30); do
        curl --silent --fail "http://${addr}/v2/" >/dev/null && { echo "${addr}"; return 0; }
        sleep 1
    done
    echo "mirror-manifests-test: registry ${container} did not become ready" >&2
    return 1
}

src_registry="$(start_registry "${name}-src")"
dst_registry="$(start_registry "${name}-dst")"

printf 'FROM scratch\nCOPY Dockerfile /\n' >"${work}/Dockerfile"
for arch in ${arches}; do
    docker buildx build --builder default --quiet --load --platform "linux/${arch}" --tag "${name}:${arch}" "${work}" >/dev/null
done

# Stand-in crane that can advance main after a matching call or inject a
# synthetic registry error on a chosen subcommand (FAIL_SUBCMD, default copy)
# to exercise retry, fail-fast and stale-head-during-backoff logic.
mkdir -p "${work}/shim"
cat >"${work}/shim/crane" <<SHIM
#!/bin/bash
advance_main() {
    if [ ! -e "\${CASE_DIR}/advanced" ]; then
        touch "\${CASE_DIR}/advanced"
        next="\$(git -C "\${CASE_DIR}/repo" commit-tree -p HEAD -m next 'HEAD^{tree}')"
        git -C "\${CASE_DIR}/repo" push --quiet origin "\${next}:refs/heads/main"
    fi
}
if [ -n "\${FAIL_MSG:-}" ] && [ "\$1" = "\${FAIL_SUBCMD:-copy}" ]; then
    count=0
    [ -f "\${FAIL_COUNT_FILE}" ] && count="\$(cat "\${FAIL_COUNT_FILE}")"
    count=\$((count + 1))
    echo "\${count}" >"\${FAIL_COUNT_FILE}"
    if [ "\${count}" -le "\${FAIL_TIMES:-1}" ]; then
        echo "\${FAIL_MSG}" >&2
        if [ "\${ADVANCE_ON_FAIL:-0}" = "1" ]; then
            advance_main
        fi
        exit 1
    fi
fi
"${real_crane}" "\$@" || exit
if [ -n "\${ADVANCE_AFTER:-}" ] && [[ "\$*" == *"\${ADVANCE_AFTER}"* ]]; then
    advance_main
fi
SHIM
chmod +x "${work}/shim/crane"

# holds <registry> <image>:<tag>: sorted child manifest digests in the index,
# "none" when the tag is genuinely absent (MANIFEST_UNKNOWN/NAME_UNKNOWN/404),
# or "ERROR" on any other lookup or parse failure so a broken registry never
# satisfies a negative assertion.
holds() {
    local out_file err_file rc found
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    set +e
    "${real_crane}" manifest "$1/${name}/$2" >"${out_file}" 2>"${err_file}"
    rc=$?
    set -e
    if [ "${rc}" -ne 0 ]; then
        if grep -Eiq 'MANIFEST_UNKNOWN|NAME_UNKNOWN|404' "${err_file}"; then
            rm -f "${out_file}" "${err_file}"
            echo "none"
            return 0
        fi
        echo "mirror-manifests-test: unexpected crane manifest failure for $1/${name}/$2:" >&2
        cat "${err_file}" >&2
        rm -f "${out_file}" "${err_file}"
        echo "ERROR"
        return 0
    fi
    if ! found="$(python3 - "${out_file}" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    doc = json.load(fh)
digests = sorted(m["digest"] for m in doc.get("manifests") or [])
if not digests:
    sys.exit(1)
print(" ".join(digests))
PY
)"; then
        echo "mirror-manifests-test: malformed or non-index manifest for $1/${name}/$2" >&2
        rm -f "${out_file}" "${err_file}"
        echo "ERROR"
        return 0
    fi
    rm -f "${out_file}" "${err_file}"
    echo "${found}"
}

# setup_case <case>: creates a repo on main and publishes multi-arch <case>/a
# and <case>/b to src_registry under :<short_sha>. Sets case_dir, sha,
# short_sha and date.
setup_case() {
    local case_name="$1" image arch sources
    case_dir="${work}/${case_name}"
    mkdir -p "${case_dir}/repo/.github/scripts" "${case_dir}/repo/components"
    cp "${script}" "${case_dir}/repo/.github/scripts/"
    cp components/target-arch "${case_dir}/repo/components/"
    git init --quiet --bare "${case_dir}/origin.git"
    git -C "${case_dir}/repo" init --quiet --initial-branch main
    git -C "${case_dir}/repo" add .
    git -C "${case_dir}/repo" -c user.name=test -c user.email=test@example.org commit --quiet -m "${case_name}"
    git -C "${case_dir}/repo" remote add origin "${case_dir}/origin.git"
    git -C "${case_dir}/repo" push --quiet origin main
    sha="$(git -C "${case_dir}/repo" rev-parse HEAD)"
    short_sha="$(printf '%.7s' "${sha}")"
    date="$(TZ=UTC git -C "${case_dir}/repo" show --no-patch --date=format-local:%Y-%m-%d --format=%cd HEAD)"
    for image in a b; do
        sources=()
        for arch in ${arches}; do
            docker tag "${name}:${arch}" "${src_registry}/${name}/${case_name}/${image}:run-${arch}"
            docker push --quiet "${src_registry}/${name}/${case_name}/${image}:run-${arch}" >/dev/null
            sources+=("${src_registry}/${name}/${case_name}/${image}:run-${arch}")
        done
        docker buildx imagetools create --tag "${src_registry}/${name}/${case_name}/${image}:${short_sha}" "${sources[@]}" >/dev/null
    done
}

# run_mirror <case> [ENV=VAL ...]: runs mirror-manifests capturing output to
# ${case_dir}/mirror.log, and dumps the log if it fails unexpectedly.
run_mirror() {
    local case_name="$1"
    shift
    local log="${case_dir}/mirror.log" rc=0
    env PATH="${work}/shim:${PATH}" CASE_DIR="${case_dir}" GITHUB_SHA="${sha}" \
        CRANE_RETRY_DELAYS="1" \
        GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.org \
        GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.org \
        "$@" \
        "${case_dir}/repo/.github/scripts/mirror-manifests" \
        "${src_registry}/${name}" "${dst_registry}/${name}" "${case_name}/a" "${case_name}/b" \
        >"${log}" 2>&1 || rc=$?
    if [ "${rc}" -ne 0 ] && [ "${EXPECT_FAIL:-0}" != "1" ]; then
        echo "mirror-manifests-test: case '${case_name}' failed unexpectedly (exit ${rc}):" >&2
        cat "${log}" >&2
    fi
    return "${rc}"
}

failed=0
# expect <what> <dst-tag> <src-tag it must equal, or none>
expect() {
    local want=none got
    [ "$3" = none ] || want="$(holds "${src_registry}" "$3")"
    got="$(holds "${dst_registry}" "$2")"
    if [ "${got}" = "${want}" ] && [ "${got}" != ERROR ] && { [ "$3" = none ] || [ "${want}" != none ]; }; then
        echo "ok: $1"
    else
        echo "FAIL: $1 (${dst_registry} $2 holds '${got}', expected '${want}')" >&2
        failed=1
    fi
}

setup_case joining
run_mirror joining ADVANCE_AFTER="manifest "
expect "main advanced during pass 1: a has its short SHA" "joining/a:${short_sha}" "joining/a:${short_sha}"
expect "main advanced during pass 1: b has its short SHA" "joining/b:${short_sha}" "joining/b:${short_sha}"
expect "main advanced during pass 1: a:latest stays" "joining/a:latest" none
expect "main advanced during pass 1: b:latest stays" "joining/b:latest" none
expect "main advanced during pass 1: a:${date} stays" "joining/a:${date}" none

setup_case between_tags
run_mirror between_tags ADVANCE_AFTER="between_tags/a:${short_sha} ${date}"
expect "main advanced between date and latest: a:${date} moved" "between_tags/a:${date}" "between_tags/a:${short_sha}"
expect "main advanced between date and latest: a:latest stays" "between_tags/a:latest" none
expect "main advanced between date and latest: b:${date} stays" "between_tags/b:${date}" none
expect "main advanced between date and latest: b:latest stays" "between_tags/b:latest" none

setup_case tagging
run_mirror tagging ADVANCE_AFTER="tagging/a:${short_sha} latest"
expect "main advanced after a's rolling tags moved: a:latest moved" "tagging/a:latest" "tagging/a:${short_sha}"
expect "main advanced after a's rolling tags moved: a:${date} moved" "tagging/a:${date}" "tagging/a:${short_sha}"
expect "main advanced after a's rolling tags moved: b:latest stays" "tagging/b:latest" none

setup_case backoff_stale
fail_file="${case_dir}/fail_count"
run_mirror backoff_stale \
    FAIL_SUBCMD="tag" \
    FAIL_MSG="DENIED: System is currently read-only" \
    FAIL_TIMES=1 \
    FAIL_COUNT_FILE="${fail_file}" \
    ADVANCE_ON_FAIL=1
expect "main advanced during tag retry backoff: a:${date} stays" "backoff_stale/a:${date}" none
expect "main advanced during tag retry backoff: a:latest stays" "backoff_stale/a:latest" none
if [ "$(cat "${fail_file}")" -eq 1 ]; then
    echo "ok: main advancing during tag retry backoff skipped retry"
else
    echo "FAIL: expected 1 tag attempt before aborting stale retry, got $(cat "${fail_file}")" >&2
    failed=1
fi

setup_case steady
run_mirror steady
expect "main stayed: a:${short_sha} mirrored" "steady/a:${short_sha}" "steady/a:${short_sha}"
expect "main stayed: a:latest moved" "steady/a:latest" "steady/a:${short_sha}"
expect "main stayed: a:${date} moved" "steady/a:${date}" "steady/a:${short_sha}"
expect "main stayed: b:latest moved" "steady/b:latest" "steady/b:${short_sha}"
expect "main stayed: b:${date} moved" "steady/b:${date}" "steady/b:${short_sha}"

setup_case quay_readonly
fail_file="${case_dir}/fail_count"
run_mirror quay_readonly \
    FAIL_MSG="DENIED: System is currently read-only" \
    FAIL_TIMES=1 \
    FAIL_COUNT_FILE="${fail_file}"
expect "Quay read-only maintenance retried and succeeded" "quay_readonly/a:latest" "quay_readonly/a:${short_sha}"
# Two images copied + 1 failed attempt on the first copy = 3 copy invocations.
if [ "$(cat "${fail_file}")" -eq 3 ]; then
    echo "ok: Quay read-only triggered exactly one retry"
else
    echo "FAIL: expected 3 copy calls (1 failed + 2 succeeded), got $(cat "${fail_file}")" >&2
    failed=1
fi

setup_case auth_fail
fail_file="${case_dir}/fail_count"
if EXPECT_FAIL=1 run_mirror auth_fail \
    FAIL_MSG="UNAUTHORIZED: authentication required" \
    FAIL_TIMES=3 \
    FAIL_COUNT_FILE="${fail_file}"; then
    echo "FAIL: auth error should have failed" >&2
    failed=1
elif [ "$(cat "${fail_file}")" -eq 1 ]; then
    echo "ok: auth error failed fast without retrying"
else
    echo "FAIL: auth error retried ($(cat "${fail_file}") attempts instead of 1)" >&2
    failed=1
fi

exit "${failed}"
