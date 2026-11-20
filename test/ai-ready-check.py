#!/usr/bin/env python3
"""Checks an AI Ready session the way its user reaches it: through the
notebook server, under a nested URL. Called by ai-ready-smoke.sh.

    ai-ready-check.py first     <base url> <token>   a session on a new home
    ai-ready-check.py again     <base url> <token>   restarted on the same home
    ai-ready-check.py recovered <base url> <token>   started again after a kill
    ai-ready-check.py kernel    <base url> <token>

All but `kernel` need only the standard library and run outside the
container. `again` and `recovered` expect what `first` created to still be
there; `recovered` checks only that. `kernel` runs inside the container with
Jupyter's Python, which has the websocket client that talking to a kernel
needs.
"""

import json
import re
import sys
import time
from datetime import datetime, timezone
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

MODE, BASE, TOKEN = sys.argv[1:4]
BASE_PATH = urlsplit(BASE).path
EXPERIMENT = "scidesktop-smoke"
DAG = "pathogenicity_training"


def request(path, data=None, authenticated=True, method=None, bearer=None):
    headers = {"Authorization": f"token {TOKEN}"} if authenticated else {}
    if bearer:
        # Airflow wants its own token in the header, so Jupyter's goes in the URL.
        headers["Authorization"] = f"Bearer {bearer}"
        path += ("&" if "?" in path else "?") + f"token={TOKEN}"
    if data is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(data).encode()
    with urlopen(Request(BASE + path, data=data, headers=headers, method=method), timeout=60) as response:
        return response.read(), response.url


def get_json(path, **kwargs):
    return json.loads(request(path, **kwargs)[0])


def wait_for(path, seconds=300):
    deadline = time.monotonic() + seconds
    while True:
        try:
            return request(path)[0]
        except (HTTPError, OSError) as error:
            if time.monotonic() > deadline:
                raise RuntimeError(f"{path} did not answer within {seconds} seconds: {error}")
            time.sleep(2)


def ok(message):
    print(f"  ok    {message}", flush=True)


def tools():
    body, url = request("")
    assert url == BASE + "ai-ready/", f"the session opens {url}"
    links = set(re.findall(r'href="([^"]+)" target="_blank"', body.decode()))
    assert links == {BASE_PATH + path for path in
                     ("lab/tree/ai-ready/notebooks", "airflow/", "mlflow/", "desktop/")}, links
    ok("the session opens the dashboard, which links JupyterLab, Airflow, MLflow and the desktop")

    tiles = {server["name"]: server["launcher_entry"]
             for server in get_json("server-proxy/servers-info")["server_processes"]}
    for name, title in (("airflow", "Airflow"), ("mlflow", "MLflow")):
        assert tiles[name]["enabled"] and tiles[name]["title"] == title, tiles[name]
        assert tiles[name]["category"] == "AI Ready", tiles[name]
        icon, _ = request(tiles[name]["icon_url"].removeprefix(BASE_PATH))
        assert b"<svg" in icon, f"{name} icon is not an SVG"
    assert tiles["desktop"]["enabled"], "the desktop tile is gone"
    ok("JupyterLab's launcher has Airflow and MLflow tiles with icons, beside the desktop's")

    # desktop/ starts the desktop on first use; that it still serves proves
    # the component's proxy entries were added to the base's, not put in
    # their place.
    for path in ("api/status", "ai-ready/", "lab", "airflow/", "mlflow/", "desktop/"):
        assert wait_for(path), path
        try:
            _, url = request(path, authenticated=False)
            assert "/login" in url, f"{path} answered without a login, at {url}"
        except HTTPError as error:
            assert error.code in (401, 403), f"{path} without a login: HTTP {error.code}"
        ok(f"{path} serves with a login and refuses without one")

    spec = get_json("api/kernelspecs")["kernelspecs"]["ai-ready"]["spec"]
    assert spec["argv"][0] == "/opt/ai-ready/env/bin/python", spec["argv"]
    ok(f"kernel offered: {spec['display_name']}")

    notebooks = [item["path"] for item in get_json("api/contents/ai-ready/notebooks")["content"]
                 if item["name"].endswith(".ipynb")]
    assert notebooks, "no workshop notebooks in ~/ai-ready/notebooks"
    for path in notebooks:
        kernel = get_json(f"api/contents/{path}")["content"]["metadata"]["kernelspec"]["name"]
        assert kernel == "ai-ready", f"{path} opens with the {kernel} kernel"
    ok(f"{len(notebooks)} workshop notebooks seeded, opening with the ai-ready kernel")


def experiment(kept):
    wait_for("mlflow/")
    try:
        created = get_json("mlflow/api/2.0/mlflow/experiments/create", data={"name": EXPERIMENT})
        assert not kept, "the MLflow experiment from the session before is gone"
        ok(f"MLflow experiment created ({created['experiment_id']})")
    except HTTPError as error:
        assert error.code == 400 and b"RESOURCE_ALREADY_EXISTS" in error.read()
        assert kept, "a new home already has the smoke test's MLflow experiment"
        ok("MLflow experiment is still there")
    found = get_json("mlflow/api/2.0/mlflow/experiments/get-by-name?experiment_name=" + EXPERIMENT)
    assert found["experiment"]["name"] == EXPERIMENT


def airflow_token():
    wait_for("airflow/")
    return get_json("airflow/auth/token")["access_token"]


def dag_run():
    """A real workshop DAG, through the proxy the browser uses: the scheduler,
    the task execution API, the workshop's libraries and MLflow together."""
    token = airflow_token()
    dag = f"airflow/api/v2/dags/{DAG}"
    deadline = time.monotonic() + 600
    while True:
        try:
            request(dag, {"is_paused": False}, method="PATCH", bearer=token)
            break
        except HTTPError as error:
            if error.code != 404 or time.monotonic() > deadline:
                raise
            time.sleep(2)
    # The workshop's DAG fails a model under its quality threshold, and the
    # unseeded training lands on either side of it. That gate is not under test.
    request("airflow/api/v2/variables/vep_mcc_threshold",
            {"key": "vep_mcc_threshold", "value": "0"}, method="PATCH", bearer=token)
    run = "smoke-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f")
    request(dag + "/dagRuns", {"dag_run_id": run, "logical_date": None}, bearer=token)
    while True:
        state = get_json(f"{dag}/dagRuns/{run}", bearer=token)["state"]
        if state == "success":
            break
        assert state != "failed", f"the {DAG} DAG failed; see the task logs under ~/.ai-ready/airflow/logs"
        assert time.monotonic() < deadline, f"the {DAG} DAG is still {state} after 10 minutes"
        time.sleep(2)
    ok(f"the {DAG} DAG ran to success")


def past_runs():
    runs = get_json(f"airflow/api/v2/dags/{DAG}/dagRuns", bearer=airflow_token())["dag_runs"]
    assert any(run["state"] == "success" for run in runs), "Airflow lost its earlier DAG runs"
    ok("Airflow still has its earlier DAG runs")


def kernel():
    import asyncio
    import uuid

    from tornado.websocket import websocket_connect

    code = ("import sys, mlflow, vep_pipeline\n"
            "print('KERNEL', sys.executable, mlflow.get_tracking_uri(), vep_pipeline.__file__)")
    started = get_json("api/kernels", data={"name": "ai-ready"})

    async def run():
        url = f"ws{BASE.removeprefix('http')}api/kernels/{started['id']}/channels?token={TOKEN}"
        socket = await websocket_connect(url)
        await socket.write_message(json.dumps({
            "channel": "shell",
            "header": {"msg_id": uuid.uuid4().hex, "msg_type": "execute_request",
                       "username": "", "session": uuid.uuid4().hex, "version": "5.3"},
            "parent_header": {}, "metadata": {},
            "content": {"code": code, "silent": False},
        }))
        while True:
            message = json.loads(await asyncio.wait_for(socket.read_message(), 120))
            content = message["content"]
            if message["msg_type"] == "error":
                raise AssertionError("\n".join(content["traceback"]))
            if message["msg_type"] == "stream" and content["text"].startswith("KERNEL"):
                return content["text"].split()[1:]

    try:
        executable, tracking, module = asyncio.run(run())
    finally:
        request(f"api/kernels/{started['id']}", method="DELETE")
    assert executable == "/opt/ai-ready/env/bin/python", executable
    assert tracking == f"http://127.0.0.1:5000{BASE_PATH}mlflow", tracking
    assert module.endswith("/ai-ready/src/vep_pipeline.py"), module
    ok("a notebook kernel imports the workshop's modules and finds MLflow")


if MODE in ("first", "again"):
    wait_for("api/status")
    tools()
    experiment(kept=MODE == "again")
    dag_run()
elif MODE == "recovered":
    wait_for("api/status")
    experiment(kept=True)
    past_runs()
elif MODE == "kernel":
    kernel()
else:
    sys.exit(__doc__)
