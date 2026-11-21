#!/bin/bash
# Checks .github/scripts/publish-manifests against a registry of its own:
# which tags move when main stays, and when it advances part way through.
#
#   test/publish-manifests-test.sh
#
# Needs Docker with buildx and git. Removes what it starts.
set -euo pipefail
cd "$(dirname "$0")/.."
script="$(pwd)/.github/scripts/publish-manifests"
arches="$(components/target-arch list)"
real_docker="$(command -v docker)"
name="publish-manifests-test-$$"
work="$(mktemp -d)"
cleanup() {
    docker rm --force --volumes "${name}" >/dev/null 2>&1 || true
    docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -F "${name}" | xargs --no-run-if-empty docker image rm >/dev/null 2>&1 || true
    rm -rf "${work}"
}
trap cleanup EXIT

docker run --detach --name "${name}" --publish 127.0.0.1::5000 registry:2 >/dev/null
registry="$(docker port "${name}" 5000/tcp | head -n 1)"
registry="localhost:${registry##*:}"
for _ in $(seq 30); do
    curl --silent --fail "http://${registry}/v2/" >/dev/null && break
    sleep 1
done

printf 'FROM scratch\nCOPY Dockerfile /\n' >"${work}/Dockerfile"
for arch in ${arches}; do
    docker buildx build --builder default --quiet --load --platform "linux/${arch}" --tag "${name}:${arch}" "${work}" >/dev/null
done

# A stand-in docker that moves main forward once, after the first command
# whose arguments contain ADVANCE_AFTER.
mkdir "${work}/bin"
cat >"${work}/bin/docker" <<SHIM
#!/bin/bash
"${real_docker}" "\$@" || exit
if [ -n "\${ADVANCE_AFTER:-}" ] && [[ "\$*" == *"\${ADVANCE_AFTER}"* ]] && [ ! -e "\${CASE_DIR}/advanced" ]; then
    touch "\${CASE_DIR}/advanced"
    next="\$(git -C "\${CASE_DIR}/repo" commit-tree -p HEAD -m next 'HEAD^{tree}')"
    git -C "\${CASE_DIR}/repo" push --quiet origin "\${next}:refs/heads/main"
fi
SHIM
chmod +x "${work}/bin/docker"

# holds <image>:<tag>: the images the registry's index under that tag points
# at, or none. Two indexes of the same images can list them in another order.
holds() {
    local found
    found="$(curl --silent --fail --header 'Accept: application/vnd.oci.image.index.v1+json' \
        "http://${registry}/v2/${name}/${1%%:*}/manifests/${1##*:}" \
        | python3 -c 'import json, sys; print(" ".join(sorted(m["digest"] for m in json.load(sys.stdin)["manifests"])))')" || true
    echo "${found:-none}"
}

# publish <case> [<advance after>]: a repository whose commit is the head of
# its origin's main, published as that commit for the images <case>/a and
# <case>/b. Each case has its own images, so no case sees another's tags.
# Sets short_sha and date.
publish() {
    local dir="${work}/$1" sha image arch
    for image in a b; do
        for arch in ${arches}; do
            # One candidate per image and architecture, as the build jobs push them.
            docker tag "${name}:${arch}" "${registry}/${name}/$1/${image}:run-${arch}"
            docker push --quiet "${registry}/${name}/$1/${image}:run-${arch}" >/dev/null
        done
    done
    mkdir -p "${dir}/repo/.github/scripts" "${dir}/repo/components"
    cp "${script}" "${dir}/repo/.github/scripts/"
    cp components/target-arch "${dir}/repo/components/"
    git init --quiet --bare "${dir}/origin.git"
    git -C "${dir}/repo" init --quiet --initial-branch main
    git -C "${dir}/repo" add .
    git -C "${dir}/repo" -c user.name=test -c user.email=test@example.org commit --quiet -m "$1"
    git -C "${dir}/repo" remote add origin "${dir}/origin.git"
    git -C "${dir}/repo" push --quiet origin main
    sha="$(git -C "${dir}/repo" rev-parse HEAD)"
    short_sha="$(printf '%.7s' "${sha}")"
    date="$(TZ=UTC git -C "${dir}/repo" show --no-patch --date=format-local:%Y-%m-%d --format=%cd HEAD)"
    PATH="${work}/bin:${PATH}" CASE_DIR="${dir}" ADVANCE_AFTER="${2:-}" GITHUB_SHA="${sha}" \
        GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.org GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.org \
        "${dir}/repo/.github/scripts/publish-manifests" "${registry}/${name}" run "$1/a" "$1/b"
}

failed=0
# expect <what> <tag> <tag it must equal, or none>
expect() {
    local want=none
    [ "$3" = none ] || want="$(holds "$3")"
    if [ "$(holds "$2")" = "${want}" ] && { [ "$3" = none ] || [ "${want}" != none ]; }; then
        echo "ok: $1"
    else
        echo "FAIL: $1 ($2 holds $(holds "$2"), expected ${want})" >&2
        failed=1
    fi
}

publish joining "imagetools inspect"
expect "main advanced while the images were joined: a has its short SHA" "joining/a:${short_sha}" "joining/a:${short_sha}"
expect "main advanced while the images were joined: b has its short SHA" "joining/b:${short_sha}" "joining/b:${short_sha}"
expect "main advanced while the images were joined: a:latest stays" "joining/a:latest" none
expect "main advanced while the images were joined: b:latest stays" "joining/b:latest" none
expect "main advanced while the images were joined: a:${date} stays" "joining/a:${date}" none

publish tagging "tagging/a:latest"
expect "main advanced after a's rolling tags moved: a:latest moved" "tagging/a:latest" "tagging/a:${short_sha}"
expect "main advanced after a's rolling tags moved: b:latest stays" "tagging/b:latest" none

publish steady
expect "main stayed: a:latest moved" "steady/a:latest" "steady/a:${short_sha}"
expect "main stayed: b:latest moved" "steady/b:latest" "steady/b:${short_sha}"
expect "main stayed: b:${date} moved" "steady/b:${date}" "steady/b:${short_sha}"

exit "${failed}"
