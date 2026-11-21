#!/usr/bin/env python3
"""Checks the Agent Client Protocol adapters the way Jupyter AI uses them:
it starts each as a subprocess and speaks the protocol's first message to it.
Called by the acp-adapters component's test and by acp-adapters-smoke.sh,
with the Jupyter environment's Python.

    acp-adapters-check.py

No message goes to a model and no credential is needed: `initialize` is
answered by the adapter itself.
"""

import json
import os
import select
import shutil
import subprocess
import sys

ADAPTERS = {"codex-acp": ("Codex", "codex"), "claude-agent-acp": ("Claude Agent", "claude")}
FAILED = 0


def check(passed, message, detail=""):
    global FAILED
    if passed:
        print(f"  ok    {message}")
    else:
        FAILED += 1
        print(f"  FAIL  {message}{': ' + str(detail)[:300] if detail != '' else ''}")
    return passed


def initialize(command):
    """The adapter's answer to `initialize`, or the reason there is none."""
    process = subprocess.Popen([command], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, cwd=os.path.expanduser("~"))
    try:
        request = {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                   "params": {"protocolVersion": 1, "clientCapabilities": {}}}
        process.stdin.write((json.dumps(request) + "\n").encode())
        process.stdin.flush()
        if not select.select([process.stdout], [], [], 60)[0]:
            return "no answer within 60 s"
        return json.loads(process.stdout.readline())
    except (OSError, ValueError) as error:
        return f"{error}: {process.stderr.read(400) if process.poll() is not None else ''}"
    finally:
        process.kill()
        process.wait()


os.makedirs(os.path.expanduser("~"), exist_ok=True)
manifest = json.load(open("/opt/scidesktop/manifest.d/acp-adapters.json"))
for command, (title, agent) in ADAPTERS.items():
    found = shutil.which(command)
    if not check(found == f"/usr/local/bin/{command}", f"{command} is on the notebook server's PATH", found):
        continue
    answer = initialize(command)
    info = answer.get("result", {}).get("agentInfo", {}) if isinstance(answer, dict) else {}
    check(info.get("title") == title and info.get("version") == manifest[command],
          f"{command} {manifest[command]} answers the protocol's first message", answer)
    check(os.access(f"/opt/coding-agents/bin/{agent}", os.X_OK), f"the {agent} it runs is the image's own")

# Jupyter AI offers a persona when importing it raises nothing.
try:
    from jupyter_ai_acp_client.acp_personas import claude, codex  # noqa: F401
    check(True, "Jupyter AI's Codex and Claude personas have what they require")
except Exception as error:  # PersonaRequirementsUnmet, or an import that broke
    check(False, "Jupyter AI's Codex and Claude personas have what they require", error)

node = subprocess.run(["/opt/acp-adapters/node/bin/node", "--version"], capture_output=True, text=True).stdout.strip()
check(node == "v" + manifest["node"], f"the adapters' Node.js is {manifest['node']}", node)
check(shutil.which("node") is None and shutil.which("npm") is None, "no node or npm command is added to PATH")

sys.exit(1 if FAILED else 0)
