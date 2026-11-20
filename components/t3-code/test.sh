#!/bin/bash
# The component's own test: runs on the OS layer as the notebook user, with
# the Jupyter environment mounted at /opt/conda.
set -euo pipefail
python=/opt/conda/bin/python
lib=/opt/t3-code/lib
work="$(mktemp -d)"
server=""
trap '[ -z "${server}" ] || kill "${server}" 2>/dev/null; rm -rf "${work}"' EXIT

# The server is the pinned build, links against this OS, and is the `t3` a
# terminal finds.
version="$(sed -n 's/.*"t3-code": "\([^"]*\)".*/\1/p' /opt/scidesktop/manifest.d/t3-code.json)"
[ "$(readlink -f "$(command -v t3)")" = /opt/t3-code/app/t3 ]
[ "$(t3 --version)" = "t3 v${version}" ]
if ldd /opt/t3-code/app/t3 | grep "not found"; then exit 1; fi

# The base-path adapter still fits this client: every anchor it rewrites is
# in its bundle exactly once (rewrite_client raises otherwise), and nothing
# the page loads is left at the root of the origin.
PYTHONPATH="${lib}" "${python}" - <<'PYTHON'
import mimetypes, pathlib, re
import t3_code_proxy as proxy

prefix = "/user/someone/t3-code/"
client = pathlib.Path("/opt/t3-code/app/client")
adapted = {}
for file in sorted(client.rglob("*")):
    if file.is_file():
        path = "/" + file.relative_to(client).as_posix()
        body = file.read_bytes()
        content_type = mimetypes.guess_type(file.name)[0] or "application/octet-stream"
        if proxy.rewrite_client(body, content_type, path, prefix) != body:
            adapted[path] = True
names = " ".join(adapted)
for bundle in ("main", "index", "assets"):
    assert re.search(rf"/assets/{bundle}-[\w-]+\.js", names), f"{bundle} bundle was not adapted: {names}"
shell = proxy.rewrite_client((client / "index.html").read_bytes(), "text/html; charset=utf-8", "/", prefix).decode()
local = re.findall(r'(?:src|href)="(/(?!/)[^"]*)"', shell)
assert local and all(url.startswith(prefix) for url in local), f"the page still loads from the root of the origin: {local}"
assert f"const prefix = \"{prefix}\"" in shell and 'crossorigin="use-credentials"' in shell
preview = b"<html><head></head><body>a file the user previews</body></html>"
assert proxy.rewrite_client(preview, "text/html", "/api/files/x.html", prefix) is preview
assert proxy.rewrite_client(preview, "text/html", "/x.html", prefix) is preview
print(f"adapter fits the client: {len(adapted)} files adapted")
PYTHON

# Settings defaults fill gaps and never replace what the user set.
mkdir -p "${work}/defaults" "${work}/t3/userdata"
echo '{"a": 1, "nested": {"x": 1, "y": 2}}' > "${work}/defaults/10.json"
echo '{"a": 5, "nested": {"x": 7}, "mine": true}' > "${work}/t3/userdata/settings.json"
PYTHONPATH="${lib}" "${python}" - "${work}" <<'PYTHON'
import json, pathlib, sys
import t3_code_serve as serve

work = pathlib.Path(sys.argv[1])
serve.apply_settings_defaults(work / "t3", work / "defaults")
settings = json.loads((work / "t3/userdata/settings.json").read_text())
assert settings == {"a": 5, "nested": {"x": 7, "y": 2}, "mine": True}, settings
print("settings defaults merge")
PYTHON
for file in /etc/scidesktop/t3-code/settings.d/*.json; do "${python}" -m json.tool "${file}" >/dev/null; done

# A notebook server with this component's configuration, under a nested URL
# as JupyterHub serves it. T3 starts on the first request.
export HOME="${work}/home"
mkdir -p "${HOME}"
base=/user/t3-test/
port=18888
"${python}" -m jupyter server --no-browser --ip=127.0.0.1 --port="${port}" --ServerApp.port_retries=0 \
    --ServerApp.base_url="${base}" --IdentityProvider.token=t3-test --ServerApp.root_dir="${HOME}" \
    >"${work}/jupyter.log" 2>&1 &
server=$!
for _ in $(seq 60); do
    if curl -fsS -o /dev/null "http://127.0.0.1:${port}${base}api/status?token=t3-test" 2>/dev/null; then break; fi
    sleep 1
done
"${python}" /tmp/t3-code-check.py "http://127.0.0.1:${port}${base}" t3-test \
    || { grep -v "Skipped non-installed" "${work}/jupyter.log" | tail -n 60; exit 1; }

# T3 listens on loopback only, keeps its state in the home, and holds the
# proxy's credential where only the user can read it.
t3_pid="$(sed -n 's/.*"pid":\([0-9]*\).*/\1/p' "${HOME}/.t3/userdata/server-runtime.json")"
[ "$(readlink "/proc/${t3_pid}/exe")" = /opt/t3-code/app/t3 ]
t3_port="$(sed -n 's/.*"port":\([0-9]*\).*/\1/p' "${HOME}/.t3/userdata/server-runtime.json")"
grep -q '"host":"127.0.0.1"' "${HOME}/.t3/userdata/server-runtime.json"
[ "$(stat -c %a "${HOME}/.t3")" = 700 ]
[ "$(stat -c %a "${HOME}/.t3/jupyter-proxy-session.json")" = 600 ]
grep -q '"enableProviderUpdateChecks": false' "${HOME}/.t3/userdata/settings.json"
# The pairing token T3 prints at start is not in the notebook server's log.
if grep -qE 'Pairing URL|pair#token' "${work}/jupyter.log"; then
    echo "T3's pairing token reached the notebook server's log" >&2
    exit 1
fi

# When the notebook server stops, T3 stops with it and closes its database.
kill -TERM "${server}"
wait "${server}" || true
server=""
for _ in $(seq 30); do
    [ -e "/proc/${t3_pid}" ] || break
    sleep 1
done
if [ -e "/proc/${t3_pid}" ]; then
    echo "T3 Code (PID ${t3_pid}, port ${t3_port}) outlived the notebook server" >&2
    exit 1
fi
if [ -e "${HOME}/.t3/userdata/server-runtime.json" ] || [ -e "${HOME}/.t3/userdata/statev2.sqlite-wal" ]; then
    echo "T3 Code did not shut down cleanly" >&2
    ls -la "${HOME}/.t3/userdata" >&2
    exit 1
fi
echo "T3 Code stopped with the notebook server"

# Nothing root-owned is writable by group or others, and the user can read it all.
if find /opt/t3-code /etc/scidesktop/t3-code /etc/scidesktop/jupyter_server_config.d/t3-code.py \
        ! -type l \( -perm /022 -o ! -readable \) -print | grep .; then
    echo "bad permissions on the files above" >&2
    exit 1
fi
