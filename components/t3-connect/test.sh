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

# What T3 0.1.5's commands do after an approval, with a stand-in `t3` that
# answers from a scenario file, and a stand-in relay client that only runs.
mkdir -p "${work}/after/t3home/userdata/secrets"
cp /bin/bash "${work}/after/cloudflared"
cat > "${work}/after/t3" <<'STUB'
#!/bin/bash
here="$(dirname "$0")"
scenario="$(cat "${here}/scenario")"
status() {
    echo "{\"desired\": $1, \"authenticated\": $1, \"linked\": $1, \"relayClient\": {\"status\": \"available\"}, \"reachability\": $2}"
}
reachable='{"status": "reachable", "checkedAt": "2026-01-01T00:00:00Z", "readyConnections": 4, "protocol": "quic"}'
unreachable='{"status": "unreachable", "checkedAt": "2026-01-01T00:00:00Z", "cause": "connector_not_ready", "reason": "r", "hint": null, "fix": "f"}'
case "$2 ${scenario}" in
    "status reachable") status true "${reachable}" ;;
    "status unreachable") status true "${unreachable}" ;;
    "status never-linked") status false null ;;
    "status "*) if [ -e "${here}/unlinked" ]; then status false null; else status true null; fi ;;
    "link "*) echo "Authorized secret-refresh-token-0123456789" ;;
    "unlink never-linked")
        echo "T3 Connect is disabled locally."
        echo "The relay-side environment record was not revoked." >&2 ;;
    # T3 clears the saved link and exits 0 whatever it could not undo.
    "unlink tunnel-left")
        touch "${here}/unlinked"
        echo "T3 Connect is disabled, but the running server could not stop its tunnel." >&2
        echo "Revoked the relay-side environment record." ;;
    "unlink record-left")
        touch "${here}/unlinked"
        echo "T3 Connect is disabled locally."
        echo "Could not revoke the relay-side environment record yet. secret-refresh-token-0123456789" >&2 ;;
    "unlink "*)
        touch "${here}/unlinked"
        echo "T3 Connect is disabled locally."
        echo "Revoked the relay-side environment record." ;;
esac
STUB
chmod +x "${work}/after/t3"
PYTHONPATH=/opt/t3-code/lib:/opt/t3-connect/lib "${python}" - "${work}/after" <<'PYTHON'
import asyncio, json, os, pathlib, subprocess, sys, time, t3_connect

work = pathlib.Path(sys.argv[1])
environ = {**os.environ, "T3CODE_HOME": str(work / "t3home"), "T3CODE_CLOUDFLARED_PATH": str(work / "cloudflared")}


def start_tunnel():
    """The stand-in relay client, running until it is killed."""
    return subprocess.Popen([str(work / "cloudflared"), "-c", "read -t 600"], stdin=subprocess.PIPE)


def scenario(name):
    (work / "scenario").write_text(name)
    (work / "unlinked").unlink(missing_ok=True)


async def settled(manager, action):
    """The state once the action's command has ended."""
    await manager.action(action)
    await manager.task
    state = manager.snapshot()
    assert "secret" not in json.dumps(state), state
    return state


async def main():
    manager = t3_connect.ConnectManager(t3=str(work / "t3"), environ=environ)

    # T3 Code's own check says the relay reaches the session. The command's
    # cached access token has expired, which is the command's to refresh.
    (work / "t3home/userdata/secrets/cloud-cli-oauth-token.bin").write_text(
        json.dumps({"accessToken": "secret-access-token", "expiresAtEpochMs": 1}))
    (work / "t3home/userdata/environment-id").write_text("environment")
    scenario("reachable")
    state = await settled(manager, "link")
    assert state["state"] == "ready" and state["linked"], state
    print("ready follows T3's own reachability check, not the cached token's expiry")

    # Cancel while the approved link is still connecting: it is kept, and
    # the setup can be resumed.
    scenario("unreachable")
    await manager.action("retry")
    for _ in range(100):
        if manager.snapshot()["state"] == "connecting":
            break
        await asyncio.sleep(0.1)
    state = await manager.action("cancel")
    assert state["state"] == "cancelled" and state["linked"], state
    page = t3_connect.PAGE.read_text()
    assert "['error', 'expired', 'cancelled'].includes(value.state)" in page, "the page offers no Retry after a cancel"
    scenario("reachable")
    state = await settled(manager, "retry")
    assert state["state"] == "ready", state
    print("a setup cancelled after approval can be resumed")

    # Disconnect, while T3 reports that it cleared the link (exit 0) but the
    # relay client is still running.
    tunnel = start_tunnel()
    scenario("tunnel-left")
    state = await settled(manager, "disconnect")
    assert state["state"] == "error" and "tunnel has not been confirmed stopped" in state["message"], state
    # The tunnel has gone, but T3 does not confirm that it stopped it.
    tunnel.kill()
    tunnel.wait()
    state = await settled(manager, "disconnect")
    assert state["state"] == "error" and "tunnel has not been confirmed stopped" in state["message"], state
    # T3 confirms, and the relay client is still there.
    tunnel = start_tunnel()
    scenario("disconnected")
    started = time.monotonic()
    state = await settled(manager, "disconnect")
    assert state["state"] == "error" and "tunnel has not been confirmed stopped" in state["message"], state
    assert time.monotonic() - started < 30, "Disconnect waited too long for the relay client"
    tunnel.kill()
    tunnel.wait()
    # The relay's record of the environment was not revoked.
    scenario("record-left")
    state = await settled(manager, "disconnect")
    assert state["state"] == "error" and "relay still lists" in state["message"], state
    assert state["connections_url"] == "https://app.t3.codes/settings/general", state
    scenario("disconnected")
    state = await settled(manager, "disconnect")
    assert state["state"] == "idle" and not state["linked"] and state["message"].startswith("Disconnected."), state
    # Nothing was ever linked: T3 has no record to revoke, and says it revoked none.
    scenario("never-linked")
    state = await settled(manager, "disconnect")
    assert state["state"] == "idle" and state["message"].startswith("Disconnected."), state
    print("Disconnect reports success only once the tunnel has stopped and T3 confirms it")

asyncio.run(main())
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
