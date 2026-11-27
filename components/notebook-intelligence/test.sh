#!/bin/bash
set -euo pipefail
export PATH="/opt/conda/bin:${PATH}"

if test -e /opt/notebook-intelligence/lib/claude_agent_sdk/_bundled; then
    echo "vendored claude_agent_sdk/_bundled binary still present" >&2
    exit 1
fi
command -v claude >/dev/null
# Match the server's sys.path order (base /opt/conda first, NBI delta appended).
python -c 'import runpy, sys; sys.path.append("/opt/notebook-intelligence/lib"); sys.argv = ["pip", "check"]; runpy.run_module("pip", run_name="__main__")'
grep -q 'GNU GENERAL PUBLIC LICENSE' /opt/notebook-intelligence/licenses/LICENSE
grep -q 'Version 3' /opt/notebook-intelligence/licenses/LICENSE
grep -q 'https://github.com/plmbr/notebook-intelligence/tree/v' /opt/notebook-intelligence/licenses/SOURCE
labs=$(jupyter labextension list 2>&1)
grep -q '@plmbr/notebook-intelligence .*enabled.*OK' <<<"${labs}"
cfg=$(jupyter server --show-config 2>/dev/null)
grep -q "'notebook_intelligence': True" <<<"${cfg}"

python - <<'PY'
import json, os, socket, subprocess, tempfile, time, urllib.request

with tempfile.TemporaryDirectory() as home, tempfile.TemporaryFile(mode="w+") as log:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]

    env = {**os.environ, "HOME": home}
    proc = subprocess.Popen(
        [
            "jupyter", "server", "--no-browser", "--ip=127.0.0.1", f"--port={port}",
            "--ServerApp.port_retries=0", "--MCPExtensionApp.mcp_port=0",
            "--IdentityProvider.token=nbi-test", "--ServerApp.open_browser=False",
            f"--ServerApp.root_dir={home}",
        ],
        env=env, stdout=log, stderr=subprocess.STDOUT, text=True,
    )
    try:
        url = f"http://127.0.0.1:{port}/notebook-intelligence/capabilities"
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                log.seek(0)
                raise RuntimeError(f"jupyter server exited early ({proc.returncode}):\n{log.read()}")
            try:
                req = urllib.request.Request(url, headers={"Authorization": "token nbi-test"})
                with urllib.request.urlopen(req, timeout=5) as resp:
                    assert resp.status == 200, resp.status
                    data = json.loads(resp.read().decode())
                    assert isinstance(data, dict) and data, data
                    print("NBI capabilities keys:", sorted(data.keys()))
                    break
            except Exception:
                time.sleep(0.5)
        else:
            log.seek(0)
            raise RuntimeError(f"timed out waiting for {url}\n--- server log ---\n{log.read()}")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)
PY
