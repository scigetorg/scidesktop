#!/bin/bash
# The component's own test: runs on the OS layer as the notebook user, with
# nothing from the base image but the OS (git is the OS layer's). No network.
set -euo pipefail
export HOME="$(mktemp -d)"
trap 'chmod -R u+w "${HOME}"; rm -rf "${HOME}"' EXIT
cd "${HOME}"
git config --global user.name "scidesktop test"
git config --global user.email "test@scidesktop.invalid"

# Each command a terminal, git or git-annex looks up is the component's.
for command in datalad git-annex git-annex-shell git-annex-remote-datalad \
    git-annex-remote-datalad-archives git-annex-remote-ora git-annex-remote-ria \
    git-credential-datalad git-remote-annex; do
    [ "$(readlink -f "$(command -v "${command}")")" = "/opt/datalad/bin/${command}" ]
done

# The manifest names the versions that answer.
manifest=/opt/scidesktop/manifest.d/datalad.json
version() { sed -n "s/.*\"$1\": \"\([^\"]*\)\".*/\1/p" "${manifest}"; }
[ "$(datalad --version)" = "datalad $(version datalad)" ]
git annex version --raw | grep -F "$(version git-annex)"
datalad containers-list --help >/dev/null

# A dataset keeps a file in the annex and gets it back from a clone: DataLad,
# git and git-annex working together.
datalad create -c text2git origin
head -c 4096 /dev/urandom > origin/data.bin
echo "notes" > origin/notes.txt
datalad save -d origin -m "add files"
[ -L origin/data.bin ] && [ ! -L origin/notes.txt ]
datalad clone origin clone
[ ! -e clone/data.bin ]
datalad get -d clone clone/data.bin
cmp origin/data.bin clone/data.bin
[ "$(datalad -f '{state}' status -d clone | sort -u)" = clean ]

# git-annex is AGPL: its licence and where its source is come with it.
grep -q "GNU AFFERO GENERAL PUBLIC LICENSE" /opt/datalad/licenses/git-annex-AGPL
grep -q "$(version git-annex)" /opt/datalad/licenses/git-annex-SOURCE

# Nothing root-owned is writable by group or others, and the user can read it all.
if find /opt/datalad ! -type l \( -perm /022 -o ! -readable \) -print | grep .; then
    echo "bad permissions on the files above" >&2
    exit 1
fi
