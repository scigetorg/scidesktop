#!/bin/bash
# End-to-end check of an image that copies the antigravity-acp component.
#
#   ./test/antigravity-acp-smoke.sh [image]
set -uo pipefail

IMAGE="${1:-scidesktop}"
FAILED=0

pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; FAILED=$((FAILED + 1)); }

echo "antigravity-acp smoke: ${IMAGE}"

out="$(docker run --rm --entrypoint /opt/conda/bin/python -i "${IMAGE}" - <<'PY' 2>&1
import json, os, pathlib, re, select, shutil, subprocess, sys, tempfile, time

manifest = json.loads(pathlib.Path("/opt/scidesktop/manifest.d/antigravity-acp.json").read_text())
version = manifest["antigravity-acp"]

found = shutil.which("agy_acp_server.par")
assert found == "/usr/local/bin/agy_acp_server.par", found
real_exe = pathlib.Path(found).resolve()
harness = real_exe.parent / "localharness_external"
assert real_exe == pathlib.Path("/opt/antigravity-acp/agy_acp_server.par"), real_exe
assert os.access(real_exe, os.X_OK) and os.access(harness, os.X_OK)
print("path=ok")

# Confirm T3 Code's embedded ANTIGRAVITY_RELEASE_VERSION matches the bundled binary.
t3_bin = pathlib.Path("/opt/t3-code/app/t3")
if t3_bin.exists():
    m = re.search(rb'ANTIGRAVITY_RELEASE_VERSION = "([^"]+)"', t3_bin.read_bytes())
    assert m and m.group(1).decode() == version, f"t3 expects {m.group(1).decode() if m else None}, have {version}"
    print("t3_version_match=ok")

# Confirm T3 Code's server_environment exposes node for Antigravity sign-in
# without putting node on the user's shell PATH.
if pathlib.Path("/opt/t3-code/lib/t3_code_serve.py").exists():
    sys.path.insert(0, "/opt/t3-code/lib")
    import t3_code_serve
    env = t3_code_serve.server_environment(pathlib.Path("/tmp/t3-test"))
    node_in_t3 = shutil.which("node", path=env.get("PATH", ""))
    assert node_in_t3 == "/opt/code-server/lib/node", node_in_t3
    assert shutil.which("node") is None
    print("t3_node_env=ok")

# Run a real ACP initialize handshake against agy_acp_server.par.
with tempfile.TemporaryDirectory(prefix="agy-smoke-") as tmp:
    env = dict(os.environ, HOME=tmp, TMPDIR=tmp, ANTIGRAVITY_HARNESS_PATH=str(harness))
    proc = subprocess.Popen(
        [str(real_exe), "--uid="],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        cwd=tmp, env=env,
    )
    try:
        req = {
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {"protocolVersion": 1, "clientInfo": {"name": "smoke", "version": "0.0.0"}, "clientCapabilities": {}},
        }
        proc.stdin.write((json.dumps(req) + "\n").encode())
        proc.stdin.flush()
        end = time.monotonic() + 60.0
        answer = None
        while time.monotonic() < end:
            ready, _, _ = select.select([proc.stdout], [], [], max(0.1, end - time.monotonic()))
            if not ready:
                break
            line = proc.stdout.readline()
            if not line:
                break
            text = line.decode("utf-8", errors="replace").strip()
            if text.startswith("{"):
                msg = json.loads(text)
                if msg.get("id") == 1:
                    answer = msg
                    break
        assert answer is not None, f"no response rc={proc.poll()} stderr={proc.stderr.read(1000) if proc.poll() is not None else b''}"
        res = answer.get("result") or {}
        info = res.get("agentInfo") or {}
        assert info.get("name") == "antigravity-acp" and info.get("version") == version, answer
        assert any(m.get("id") == "oauth-personal" for m in (res.get("authMethods") or [])), answer
        print("acp_init=ok")
    finally:
        proc.kill()
        proc.wait()
PY
)"

grep -qx 'path=ok' <<<"${out}" && pass "agy_acp_server.par on PATH resolves alongside localharness_external" || fail "agy_acp_server.par path resolution"
grep -qx 't3_version_match=ok' <<<"${out}" && pass "antigravity-acp version matches T3 Code's embedded release table" || fail "antigravity-acp version matches T3 Code"
grep -qx 't3_node_env=ok' <<<"${out}" && pass "T3 Code server environment finds node for Antigravity sign-in without polluting shell PATH" || fail "T3 Code server environment node lookup"
grep -qx 'acp_init=ok' <<<"${out}" && pass "agy_acp_server.par answers ACP initialize with oauth-personal" || fail "agy_acp_server.par ACP initialize"

if [ "${FAILED}" -ne 0 ]; then
    printf '%s\n' "${out}" | sed 's/^/        /'
fi

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "antigravity-acp smoke: all checks passed"
else
    echo "antigravity-acp smoke: ${FAILED} check(s) failed"
fi
exit "${FAILED}"
