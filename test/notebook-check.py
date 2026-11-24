#!/opt/conda/bin/python3
"""End-to-end check of Jupyter Contents CRUD, WebSocket kernel execution,
MODULEPATH/Lmod inheritance inside a running kernel, error recovery, and
nbconvert execution. Runs inside the image against its local Jupyter server.
"""

from __future__ import annotations

import asyncio
import json
import subprocess
import sys
import urllib.request
import uuid

from tornado.websocket import websocket_connect

BASE = sys.argv[1].rstrip("/")
TOKEN = sys.argv[2]
HEADERS = {"Authorization": f"token {TOKEN}", "Content-Type": "application/json"}


def api(method: str, path: str, body: dict | None = None) -> tuple[int, dict | None]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{BASE}{path}", data=data, headers=HEADERS, method=method)
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read()
        return resp.status, json.loads(raw) if raw else None


async def execute_cell(ws, code: str, timeout: float = 30.0) -> dict:
    msg_id = uuid.uuid4().hex
    msg = {
        "header": {
            "msg_id": msg_id,
            "username": "smoke",
            "session": uuid.uuid4().hex,
            "msg_type": "execute_request",
            "version": "5.3",
        },
        "parent_header": {},
        "metadata": {},
        "content": {
            "code": code,
            "silent": False,
            "store_history": False,
            "user_expressions": {},
            "allow_stdin": False,
            "stop_on_error": True,
        },
        "buffers": [],
        "channel": "shell",
    }
    await ws.write_message(json.dumps(msg))
    stdout: list[str] = []
    stderr: list[str] = []
    error: dict | None = None
    reply_status: str | None = None
    got_idle = False
    deadline = asyncio.get_running_loop().time() + timeout

    while not (reply_status is not None and got_idle):
        remaining = deadline - asyncio.get_running_loop().time()
        if remaining <= 0:
            raise TimeoutError(f"timed out executing cell: {code!r}")
        raw = await asyncio.wait_for(ws.read_message(), timeout=remaining)
        if raw is None:
            raise RuntimeError("kernel WebSocket closed unexpectedly")
        ev = json.loads(raw)
        if ev.get("parent_header", {}).get("msg_id") != msg_id:
            continue
        mtype = ev.get("msg_type")
        content = ev.get("content", {})
        if mtype == "stream":
            if content.get("name") == "stdout":
                stdout.append(content.get("text", ""))
            else:
                stderr.append(content.get("text", ""))
        elif mtype == "error":
            error = content
        elif mtype == "execute_reply":
            reply_status = content.get("status")
        elif mtype == "status" and content.get("execution_state") == "idle":
            got_idle = True

    return {
        "status": reply_status,
        "stdout": "".join(stdout),
        "stderr": "".join(stderr),
        "error": error,
    }


async def main() -> None:
    # 1. Contents CRUD
    nb_path = f"smoke_nb_{uuid.uuid4().hex[:8]}.ipynb"
    nb = {
        "cells": [
            {
                "cell_type": "code",
                "execution_count": None,
                "metadata": {},
                "outputs": [],
                "source": ["print('NBCONVERT_OK', 33 * 3)\n"],
            }
        ],
        "metadata": {
            "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
            "language_info": {"name": "python"},
        },
        "nbformat": 4,
        "nbformat_minor": 5,
    }
    status, _ = api("PUT", f"/api/contents/{nb_path}", {"type": "notebook", "format": "json", "content": nb})
    assert status in (200, 201), f"PUT contents failed: {status}"
    status, got = api("GET", f"/api/contents/{nb_path}")
    assert status == 200 and got and got["content"]["cells"][0]["source"] == "print('NBCONVERT_OK', 33 * 3)\n"
    print("  ok    Contents API creates and reads back a notebook")

    # 2. Real Python kernel over WebSocket: execution, MODULEPATH/Lmod, negative error, recovery
    status, kernel = api("POST", "/api/kernels", {"name": "python3"})
    assert status in (200, 201) and kernel and kernel.get("id"), f"kernel start failed: {status}"
    kid = kernel["id"]
    ws_base = BASE.replace("http://", "ws://", 1).replace("https://", "wss://", 1)
    ws = None
    try:
        ws = await websocket_connect(f"{ws_base}/api/kernels/{kid}/channels?token={TOKEN}")
        res = await execute_cell(
            ws,
            "import os, subprocess\n"
            "print('KERNEL_CALC=' + str(6 * 7))\n"
            "print('MODULEPATH=' + os.environ.get('MODULEPATH', ''))\n"
            "r = subprocess.run(['bash', '-lc', 'type -t module'], capture_output=True, text=True)\n"
            "print('LMOD_FUNC=' + r.stdout.strip())\n",
        )
        assert res["status"] == "ok", f"positive cell failed: {res}"
        assert "KERNEL_CALC=42" in res["stdout"], f"unexpected stdout: {res['stdout']!r}"
        mp_line = [ln for ln in res["stdout"].splitlines() if ln.startswith("MODULEPATH=")]
        assert mp_line and mp_line[0].split("=", 1)[1].strip(), f"empty MODULEPATH in kernel: {res['stdout']!r}"
        assert "LMOD_FUNC=function" in res["stdout"], f"Lmod missing from kernel login shell: {res['stdout']!r}"
        print("  ok    kernel executes code and inherits MODULEPATH and Lmod")

        err = await execute_cell(ws, "1 / 0")
        assert err["status"] == "error", f"expected error status: {err}"
        assert err["error"] and err["error"].get("ename") == "ZeroDivisionError", f"unexpected error: {err}"
        print("  ok    kernel reports ZeroDivisionError cleanly and returns to idle")

        rec = await execute_cell(ws, "print('RECOVERED=' + str(3 * 9))")
        assert rec["status"] == "ok" and "RECOVERED=27" in rec["stdout"], f"kernel failed to recover: {rec}"
        print("  ok    kernel stays responsive after an error")
    finally:
        if ws is not None:
            ws.close()
        api("DELETE", f"/api/kernels/{kid}")

    # 3. nbconvert --execute on the saved notebook
    out_nb = f"/tmp/executed_{uuid.uuid4().hex[:8]}.ipynb"
    proc = subprocess.run(
        ["jupyter", "nbconvert", "--to", "notebook", "--execute", "--output", out_nb, nb_path],
        capture_output=True,
        text=True,
        timeout=90,
    )
    assert proc.returncode == 0, f"nbconvert failed:\n{proc.stdout}\n{proc.stderr}"
    executed = json.load(open(out_nb))
    outputs = executed["cells"][0].get("outputs", [])
    text = "".join(
        "".join(o.get("text", [])) if isinstance(o.get("text"), list) else str(o.get("text", ""))
        for o in outputs
    )
    assert "NBCONVERT_OK 99" in text, f"nbconvert output missing expected text: {outputs!r}"
    print("  ok    jupyter nbconvert --execute runs and captures output")

    api("DELETE", f"/api/contents/{nb_path}")
    print("  ok    Contents API deletes the temporary notebook")


if __name__ == "__main__":
    asyncio.run(main())
