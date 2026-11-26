#!/usr/bin/env python3
"""Verify the Antigravity ACP server binary the way T3 Code resolves and starts it."""

import json
import os
import pathlib
import select
import shutil
import subprocess
import sys
import tempfile


def main():
    manifest = json.loads(pathlib.Path("/opt/scidesktop/manifest.d/antigravity-acp.json").read_text())
    expected_version = manifest["antigravity-acp"]

    found = shutil.which("agy_acp_server.par")
    assert found == "/usr/local/bin/agy_acp_server.par", f"unexpected PATH lookup: {found}"
    real_exe = pathlib.Path(found).resolve()
    assert real_exe == pathlib.Path("/opt/antigravity-acp/agy_acp_server.par"), real_exe
    harness = real_exe.parent / "localharness_external"
    assert os.access(real_exe, os.X_OK) and os.access(harness, os.X_OK), (real_exe, harness)

    for p in (real_exe, harness):
        mode = p.stat().st_mode
        assert not (mode & 0o022), f"group/other writable: {p} ({oct(mode)})"

    ldd = subprocess.run(["ldd", str(harness)], capture_output=True, text=True, check=False)
    assert "not found" not in ldd.stdout, ldd.stdout

    defaults = json.loads(
        pathlib.Path("/etc/scidesktop/t3-code/settings.d/30-antigravity-acp.json").read_text()
    )
    assert defaults == {"providerInstances": {"antigravity": {"driver": "antigravity", "enabled": True}}}, defaults

    with tempfile.TemporaryDirectory(prefix="agy-acp-test-") as tmp:
        env = dict(os.environ)
        env["HOME"] = tmp
        env["TMPDIR"] = tmp
        env["XDG_CONFIG_HOME"] = os.path.join(tmp, ".config")
        env["XDG_DATA_HOME"] = os.path.join(tmp, ".local", "share")
        env["ANTIGRAVITY_HARNESS_PATH"] = str(harness)
        proc = subprocess.Popen(
            [str(real_exe), "--uid="],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=tmp,
            env=env,
        )
        try:
            req = {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": 1,
                    "clientInfo": {"name": "scidesktop-test", "version": "0.0.0"},
                    "clientCapabilities": {},
                },
            }
            proc.stdin.write((json.dumps(req) + "\n").encode())
            proc.stdin.flush()

            deadline = 60.0
            answer = None
            import time
            end = time.monotonic() + deadline
            while time.monotonic() < end:
                rem = max(0.1, end - time.monotonic())
                ready, _, _ = select.select([proc.stdout], [], [], rem)
                if not ready:
                    break
                line = proc.stdout.readline()
                if not line:
                    break
                text = line.decode("utf-8", errors="replace").strip()
                if not text.startswith("{"):
                    continue
                msg = json.loads(text)
                if msg.get("id") == 1:
                    answer = msg
                    break

            if answer is None:
                stderr = proc.stderr.read(2000).decode("utf-8", errors="replace") if proc.poll() is not None else ""
                raise AssertionError(f"no ACP initialize response within {deadline}s; rc={proc.poll()} stderr={stderr}")

            result = answer.get("result") or {}
            info = result.get("agentInfo") or {}
            assert info.get("name") == "antigravity-acp", answer
            assert info.get("version") == expected_version, (info, expected_version)
            auth_ids = [m.get("id") for m in result.get("authMethods") or []]
            assert "oauth-personal" in auth_ids, answer
            print(f"antigravity-acp {info['version']} initialized cleanly (auth={auth_ids})")
        finally:
            proc.kill()
            proc.wait()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
