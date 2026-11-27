#!/bin/bash
# Checks .github/scripts/mirror-manifests against local source and destination
# registries: multi-arch preservation, rolling-tag safety when main advances,
# retry on Quay read-only maintenance, and fail-fast on auth errors.
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
# synthetic registry error to exercise retry and fail-fast logic.
mkdir -p "${work}/shim"
cat >"${work}/shim/crane" <<SHIM
#!/bin/bash
if [ -n "\${FAIL_MSG:-}" ] && [ "\$1" = "copy" ]; then
    count=0
    [ -f "\${FAIL_COUNT_FILE}" ] && count="\$(cat "\${FAIL_COUNT_FILE}")"
    count=\$((count + 1))
    echo "\${count}" >"\${FAIL_COUNT_FILE}"
    if [ "\${count}" -le "\${FAIL_TIMES:-1}" ]; then
        echo "\${FAIL_MSG}" >&2
        exit 1
    fi
fi
"${real_crane}" "\$@" || exit
if [ -n "\${ADVANCE_AFTER:-}" ] && [[ "\$*" == *"\${ADVANCE_AFTER}"* ]] && [ ! -e "\${CASE_DIR}/advanced" ]; then
    touch "\${CASE_DIR}/advanced"
    next="\$(git -C "\${CASE_DIR}/repo" commit-tree -p HEAD -m next 'HEAD^{tree}')"
    git -C "\${CASE_DIR}/repo" push --quiet origin "\${next}:refs/heads/main"
fi
SHIM
chmod +x "${work}/shim/crane"

# holds <registry> <image>:<tag>: sorted child manifest digests in the index, or none.
holds() {
    local found
    found="$("${real_crane}" manifest "$1/${name}/$2" 2>/dev/null \
        | python3 -c 'import json, sys; print(" ".join(sorted(m["digest"] for m in json.load(sys.stdin).get("manifests") or [])))' \
        2>/dev/null)" || true
    echo "${found:-none}"
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

run_mirror() {
    local case_name="$1"
    shift
    env PATH="${work}/shim:${PATH}" CASE_DIR="${case_dir}" GITHUB_SHA="${sha}" \
        CRANE_RETRY_DELAYS="1" \
        GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.org \
        GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.org \
        "$@" \
        "${case_dir}/repo/.github/scripts/mirror-manifests" \
        "${src_registry}/${name}" "${dst_registry}/${name}" "${case_name}/a" "${case_name}/b"
}

failed=0
# expect <what> <dst-tag> <src-tag it must equal, or none>
expect() {
    local want=none got
    [ "$3" = none ] || want="$(holds "${src_registry}" "$3")"
    got="$(holds "${dst_registry}" "$2")"
    if [ "${got}" = "${want}" ] && { [ "$3" = none ] || [ "${want}" != none ]; }; then
        echo "ok: $1"
    else
        echo "FAIL: $1 (${dst_registry} $2 holds '${got}', expected '${want}')" >&2
        failed=1
    fi
}

setup_case joining
run_mirror joining ADVANCE_AFTER="manifest " >/dev/null 2>&1
expect "main advanced during pass 1: a has its short SHA" "joining/a:${short_sha}" "joining/a:${short_sha}"
expect "main advanced during pass 1: b has its short SHA" "joining/b:${short_sha}" "joining/b:${short_sha}"
expect "main advanced during pass 1: a:latest stays" "joining/a:latest" none
expect "main advanced during pass 1: b:latest stays" "joining/b:latest" none
expect "main advanced during pass 1: a:${date} stays" "joining/a:${date}" none

setup_case tagging
run_mirror tagging ADVANCE_AFTER="tagging/a:${short_sha} latest" >/dev/null 2>&1
expect "main advanced after a's rolling tags moved: a:latest moved" "tagging/a:latest" "tagging/a:${short_sha}"
expect "main advanced after a's rolling tags moved: a:${date} moved" "tagging/a:${date}" "tagging/a:${short_sha}"
expect "main advanced after a's rolling tags moved: b:latest stays" "tagging/b:latest" none

setup_case steady
run_mirror steady >/dev/null 2>&1
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
    FAIL_COUNT_FILE="${fail_file}" >/dev/null 2>&1
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
if run_mirror auth_fail \
    FAIL_MSG="UNAUTHORIZED: authentication required" \
    FAIL_TIMES=3 \
    FAIL_COUNT_FILE="${fail_file}" >/dev/null 2>&1; then
    echo "FAIL: auth error should have failed" >&2
    failed=1
elif [ "$(cat "${fail_file}")" -eq 1 ]; then
    echo "ok: auth error failed fast without retrying"
else
    echo "FAIL: auth error retried ($(cat "${fail_file}") attempts instead of 1)" >&2
    failed=1
fi

exit "${failed}"
