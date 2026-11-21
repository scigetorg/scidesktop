#!/bin/bash
# The component's own test: runs on the OS layer as the notebook user, with
# nothing from the base image but the OS.
set -euo pipefail
export HOME="$(mktemp -d)"
socket="${HOME}/code-server.sock"
# code-server is waited for before its home is removed: it writes there until
# it has exited, and under `set -e` a failed removal would fail the test.
trap 'kill "${pid:-}" 2>/dev/null || true; wait "${pid:-}" 2>/dev/null || true; rm -rf "${HOME}" || true' EXIT
cd "${HOME}"

# The command a terminal finds is the component's, and the manifest names the
# version that answers.
[ "$(readlink -f "$(command -v code-server)")" = /opt/code-server/bin/code-server ]
manifest=/opt/scidesktop/manifest.d/code-server.json
version="$(sed -n 's/.*"code-server": "\([^"]*\)".*/\1/p' "${manifest}")"
code-server --version | grep -F "${version}"

# It serves the editor on a Unix socket only the user can open, as the tile
# starts it, on this OS and without a network.
code-server --auth none --disable-telemetry --disable-update-check \
    --builtin-extensions-dir /usr/local/share/code-server/extensions \
    --socket "${socket}" --socket-mode 0600 "${HOME}" >"${HOME}/log" 2>&1 &
pid=$!
for _ in $(seq 1 60); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' --unix-socket "${socket}" http://localhost/healthz)" = 200 ] && break
    sleep 1
done
[ "$(stat -c %a "${socket}")" = 600 ]
# Each answer is saved before it is searched: grep -q stops reading at the
# first match, and curl then fails on a page it could not finish writing.
curl -fsS --unix-socket "${socket}" -o "${HOME}/healthz" http://localhost/healthz
grep -q '"status"' "${HOME}/healthz"
curl -fsSL --unix-socket "${socket}" -o "${HOME}/page" "http://localhost/?folder=${HOME}"
grep -q 'vscode-workbench-web-configuration' "${HOME}/page" || { cat "${HOME}/log" >&2; exit 1; }

# The system extensions folder holds every extension of the release, and is
# the one the tile starts code-server with.
[ "$(ls /usr/local/share/code-server/extensions | sort)" = "$(ls /opt/code-server/lib/vscode/extensions | sort)" ]
test -s /usr/local/share/code-server/extensions/git/package.json
grep -q '"--builtin-extensions-dir", "/usr/local/share/code-server/extensions"' \
    /etc/scidesktop/jupyter_server_config.d/code-server.py

# The tile's icon and the notices redistribution needs come with the release.
test -s /opt/code-server/src/browser/media/favicon.svg
test -s /opt/code-server/LICENSE
test -s /opt/code-server/ThirdPartyNotices.txt

# Nothing root-owned is writable by group or others, and the user can read it all.
if find /opt/code-server /usr/local/share/code-server ! -type l \( -perm /022 -o ! -readable \) -print | grep .; then
    echo "bad permissions on the files above" >&2
    exit 1
fi
