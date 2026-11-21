#!/bin/bash
# The component's own test: runs on the OS layer as the notebook user, with
# T3 Code and the Jupyter environment. It never contacts T3's services: the
# device authorization is driven with a stand-in for the `t3` command.
set -euo pipefail
python=/opt/conda/bin/python
work="$(mktemp -d)"
server=""
trap 'echo "t3-connect test: the check at line ${LINENO} failed" >&2' ERR
# The server is waited for before its folder is removed: it writes there
# until it has exited, and under `set -e` a failed removal would fail the test.
trap '[ -z "${server}" ] || { kill "${server}" 2>/dev/null; wait "${server}" 2>/dev/null; } || true; rm -rf "${work}" || true' EXIT
export HOME="${work}/home"
mkdir -p "${HOME}"

# The relay client is the pinned release, static, and the one T3 accepts.
version="$(sed -n 's/.*"cloudflared": "\([^"]*\)".*/\1/p' /opt/scidesktop/manifest.d/t3-connect.json)"
/opt/t3-connect/bin/cloudflared --version | grep -qF "version ${version} "
if ldd /opt/t3-connect/bin/cloudflared 2>/dev/null | grep "not found"; then exit 1; fi
status="$(PYTHONPATH=/opt/t3-code/lib:/opt/t3-connect/lib "${python}" - <<'PYTHON'
import asyncio, json, t3_connect
print(json.dumps(asyncio.run(t3_connect.ConnectManager().saved_status())))
PYTHON
)"
grep -q '"relayClient": {"status": "available"' <<<"${status}" || { echo "${status}" >&2; false; }
# Off by default: nothing is desired, authenticated or linked.
grep -q '"desired": false, "authenticated": false, "linked": false' <<<"${status}"

# The device authorization, with a stand-in `t3`: the code reaches the state
# the signed-in user is shown, nothing else of the output does, and Cancel
# ends the command.
cat > "${work}/t3" <<'STUB'
#!/bin/bash
if [ "$1 $2" = "connect status" ]; then
    echo '{"desired": false, "authenticated": false, "linked": false, "relayClient": {"status": "available"}}'
    exit 0
fi
echo "secret-refresh-token-0123456789"
echo "Confirm this code when asked: ABCD-2345"
echo "Waiting for approval (expires in 9 min)"
echo $$ > "$(dirname "$0")/t3.pid"
exec sleep 600
STUB
chmod +x "${work}/t3"
PYTHONPATH=/opt/t3-code/lib:/opt/t3-connect/lib "${python}" - "${work}" <<'PYTHON'
import asyncio, json, os, pathlib, sys, t3_connect

work = pathlib.Path(sys.argv[1])

async def main():
    manager = t3_connect.ConnectManager(t3=str(work / "t3"))
    assert manager.snapshot()["state"] == "idle" and not manager.snapshot()["linked"]
    await manager.action("link")
    for _ in range(100):
        if manager.snapshot()["code"]:
            break
        await asyncio.sleep(0.1)
    state = manager.snapshot()
    assert state["state"] == "authorizing" and state["code"] == "ABCD-2345", state
    assert state["verification_url"] == "https://accounts.t3.codes/device", state
    assert 500 < state["expires_at"] - __import__("time").time() <= 540, state
    assert "secret-refresh-token" not in json.dumps(state), state
    pid = int((work / "t3.pid").read_text())
    state = await manager.action("cancel")
    assert state["state"] == "idle" and state["code"] is None, state
    await asyncio.sleep(0.3)
    assert not os.path.exists(f"/proc/{pid}"), "Cancel left the authorization command running"
    try:
        await manager.action("format-disk")
        raise AssertionError("an unknown action was accepted")
    except Exception as error:
        assert getattr(error, "status_code", None) == 400, error

asyncio.run(main())
print("device authorization: the code is shown, the rest is not, Cancel ends it")
PYTHON

# T3 Code learns of the relay client and of the page through its extension
# points, and of nothing when the files are absent.
PYTHONPATH=/opt/t3-code/lib "${python}" - "${work}" <<'PYTHON'
import pathlib, sys
import t3_code_proxy as proxy, t3_code_serve as serve

work = pathlib.Path(sys.argv[1])
assert serve.server_environment(work, {})["T3CODE_CLOUDFLARED_PATH"] == "/opt/t3-connect/bin/cloudflared"
# The relay client's own status port stays on loopback, whatever it would choose.
assert serve.server_environment(work, {})["TUNNEL_METRICS"] == "127.0.0.1:0"
assert serve.server_environment(work, {"T3CODE_CLOUDFLARED_PATH": "/mine"})["T3CODE_CLOUDFLARED_PATH"] == "/mine"
assert "T3CODE_CLOUDFLARED_PATH" not in serve.server_environment(work, {}, work / "none")
assert proxy.connect_url("/user/someone/t3-code/") == "/user/someone/t3-connect/"
assert proxy.connect_url("/user/someone/t3-code/", work / "none") is None
shell = proxy.rewrite_client(pathlib.Path("/opt/t3-code/app/client/index.html").read_bytes(),
                             "text/html", "/", "/user/someone/t3-code/").decode()
assert 'const connect = "/user/someone/t3-connect/";' in shell
print("T3 Code's extension points carry the relay client and the page")
PYTHON

# A notebook server with both components' configuration, under a nested URL.
base=/user/t3-connect-test/
port="$("${python}" -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
"${python}" -m jupyter server --no-browser --ip=127.0.0.1 --port="${port}" --ServerApp.port_retries=0 \
    --ServerApp.base_url="${base}" --IdentityProvider.token=t3-connect-test --ServerApp.root_dir="${HOME}" \
    >"${work}/jupyter.log" 2>&1 &
server=$!
for _ in $(seq 60); do
    if curl -fsS -o /dev/null "http://127.0.0.1:${port}${base}api/status?token=t3-connect-test" 2>/dev/null; then break; fi
    sleep 1
done
"${python}" /tmp/t3-connect-check.py "http://127.0.0.1:${port}${base}" t3-connect-test \
    || { grep -v "Skipped non-installed" "${work}/jupyter.log" | tail -n 40; exit 1; }
# Looking at the page started nothing.
if pgrep -x cloudflared >/dev/null || pgrep -f '^/opt/t3-code/app/t3 serve ' >/dev/null; then
    echo "T3 Connect's page started a process" >&2
    exit 1
fi

# Nothing root-owned is writable by group or others, and the user can read it all.
if find /opt/t3-connect /etc/scidesktop/t3-code /etc/scidesktop/jupyter_server_config.d/t3-connect.py /etc/profile.d/t3-connect.sh /etc/bash.bashrc.d/t3-connect.sh \
        ! -type l \( -perm /022 -o ! -readable \) -print | grep .; then
    echo "bad permissions on the files above" >&2
    exit 1
fi
echo "t3-connect: off by default, behind the login, and the code stays with the user"
