"""T3 Connect for the session's T3 Code: remote access from the T3 desktop and
mobile apps through T3's relay, set up from a page behind the notebook
server's login.

Ported from neurodesk/neurodesktop (extensions/t3-code-server/
neurodesk_t3_code/connect.py, MIT, Copyright (c) 2021 NeuroDesk), for a T3
Code that Jupyter Server Proxy starts on demand.

    <session URL>/t3-connect/      the page
    <session URL>/t3-connect/api   GET: the state; POST {"action": ...}

Connect is off until the user asks for it on the page. Then the pinned `t3`
command runs T3's device authorization, and T3 Code opens an outbound tunnel
to T3's relay with the relay client the component ships. Nothing listens
beyond loopback.

The command's output is untrusted and never returned or logged wholesale: one
bounded device code is read from it and shown to the signed-in user. The
account's credentials stay in T3's private store (~/.t3/userdata/secrets),
which only the `t3` command reads.
"""

import asyncio
from contextlib import suppress
import json
import os
from pathlib import Path
import re
import signal
import sqlite3
import time

from jupyter_server.base.handlers import APIHandler, JupyterHandler
from jupyter_server.utils import url_path_join
from tornado import web

from t3_code_proxy import base_dir
from t3_code_serve import T3, server_environment

ROUTE = "t3-connect"
PAGE = Path(__file__).with_name("t3_connect.html")
DEVICE_PAGE = "https://accounts.t3.codes/device"
CONNECTIONS_PAGE = "https://app.t3.codes/settings/general"
DEFAULT_TUNNEL_LIMIT = 3
AUTH_TIMEOUT = 660
ROUTE_TIMEOUT = 240
# `t3 connect status` asks the running server to check its tunnel, and waits
# 30 seconds for the answer.
STATUS_TIMEOUT = 45


class ConnectError(Exception):
    """A deliberately credential-free user-facing failure."""

    def __init__(self, message, *, connections_url=None):
        super().__init__(message)
        self.connections_url = connections_url


class ConnectManager:
    """One session's T3 Connect setup. `t3` is the command to run."""

    def __init__(self, t3=T3, environ=os.environ):
        self.t3 = t3
        self.environ = environ
        self.state = "idle"
        self.message = "T3 Connect is off. T3 Code works here without it."
        self.code = None
        self.expires_at = None
        self.linked = False
        self.connections_url = None
        self.last_checked = 0
        self.task = None
        self.lock = asyncio.Lock()

    @property
    def base(self):
        return base_dir(self.environ)

    def snapshot(self):
        return dict(state=self.state, message=self.message, code=self.code,
                    verification_url=DEVICE_PAGE if self.code else None,
                    expires_at=self.expires_at, linked=self.linked,
                    connections_url=self.connections_url, last_checked=self.last_checked,
                    # The page asks T3 Code for a page while this is set, which
                    # is what makes Jupyter Server Proxy start it.
                    needs_server=self.state in ("restarting", "connecting", "ready"))

    def set_state(self, state, message):
        self.state, self.message = state, message
        self.connections_url = None
        if state != "authorizing":
            self.code = self.expires_at = None

    async def _process(self, *args, timeout=30, on_line=None):
        self.base.mkdir(mode=0o700, parents=True, exist_ok=True)
        process = await asyncio.create_subprocess_exec(
            self.t3, "connect", *args, "--base-dir", str(self.base),
            env={**server_environment(self.base, self.environ), "NO_COLOR": "1"}, cwd=str(Path.home()),
            stdin=asyncio.subprocess.DEVNULL, stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL, start_new_session=True, limit=65536,
        )
        output = bytearray()
        try:
            async with asyncio.timeout(timeout):
                async for line in process.stdout:
                    output.extend(line)
                    if len(output) > 65536:
                        raise ConnectError("T3 returned an unexpected response. Please retry.")
                    if on_line:
                        on_line(line.decode("utf-8", errors="replace"))
                if await process.wait():
                    raise ConnectError("T3 Connect could not complete the request. Check your connection and retry.")
            return bytes(output)
        finally:
            if process.returncode is None:
                with suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGTERM)
                try:
                    await asyncio.wait_for(process.wait(), 3)
                except TimeoutError:
                    with suppress(ProcessLookupError):
                        os.killpg(process.pid, signal.SIGKILL)
                    await process.wait()

    async def saved_status(self):
        try:
            value = json.loads(await self._process("status", "--json", timeout=STATUS_TIMEOUT))
        except ValueError:
            value = None
        if not isinstance(value, dict):
            raise ConnectError("Could not read T3 Connect status.")
        self.linked = bool(value.get("desired") or value.get("linked"))
        return value

    def authorization_line(self, line):
        match = re.fullmatch(r"Confirm this code when asked: ([A-Z0-9]{4}-[A-Z0-9]{4})\s*", line)
        if match:
            self.set_state("authorizing", "Approve this code with the account of your T3 app.")
            self.code = match[1]
            self.expires_at = time.time() + 600
        expiry = re.search(r"Waiting for approval \(expires in (\d+) min\)", line)
        if expiry and self.code:
            self.expires_at = time.time() + min(int(expiry[1]) * 60, AUTH_TIMEOUT)

    def active_chats(self):
        """Whether a chat is running. Fails closed: unknown counts as running."""
        path = self.base / "userdata/statev2.sqlite"
        try:
            with sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, timeout=1) as db:
                return db.execute(
                    "SELECT count(*) FROM projection_thread_sessions "
                    "WHERE active_turn_id IS NOT NULL OR status IN ('running', 'starting')"
                ).fetchone()[0] != 0
        except sqlite3.Error:
            return True

    def server_pid(self):
        """The PID of this session's T3 Code server, or None when it is not running."""
        try:
            runtime = json.loads((self.base / "userdata/server-runtime.json").read_text())
            pid = int(runtime["pid"])
            if os.readlink(f"/proc/{pid}/exe") == T3:
                return pid
        except (OSError, ValueError, KeyError, TypeError):
            pass
        return None

    async def _stop_server(self):
        """Stop T3 Code so that its next start reads the saved link.

        Jupyter Server Proxy starts it again on the next request to it, which
        the page sends while `needs_server` is set.
        """
        pid = self.server_pid()
        if pid is None:
            return
        with suppress(ProcessLookupError):
            os.kill(pid, signal.SIGTERM)
        for _ in range(100):
            if not os.path.exists(f"/proc/{pid}"):
                return
            await asyncio.sleep(0.1)
        raise ConnectError("T3 Code did not stop. Close its tab, wait a moment and choose Retry.")

    async def reachable(self):
        """Whether T3's relay reaches this session, by T3 Code's own check.

        A saved link or a running relay client is not readiness. `t3 connect
        status` has the running T3 Code probe its tunnel; the credentials
        stay the command's to read and refresh.
        """
        reachability = (await self.saved_status()).get("reachability")
        return isinstance(reachability, dict) and reachability.get("status") == "reachable"

    async def _wait_reachable(self):
        deadline = asyncio.get_running_loop().time() + ROUTE_TIMEOUT
        self.set_state("connecting", "Starting the connection. This can take a few minutes.")
        while asyncio.get_running_loop().time() < deadline:
            try:
                if await self.reachable():
                    self.last_checked = time.time()
                    self.set_state("ready", "Ready. In the T3 app, open Settings, Connections and add this environment.")
                    return
            except (ConnectError, TimeoutError):
                pass
            await asyncio.sleep(3)
        raise ConnectError(
            "The link is saved, but the relay does not reach this session yet. Retry checks the saved "
            "link and refreshes the authorization if needed. A T3 account allows "
            f"{DEFAULT_TUNNEL_LIMIT} connected environments by default, so an account that is "
            "already full cannot add this one.",
            connections_url=CONNECTIONS_PAGE,
        )

    async def _link(self):
        saved = await self.saved_status()
        if saved.get("relayClient", {}).get("status") != "available":
            raise ConnectError("The relay client T3 Connect needs is not available in this image.")
        self.set_state("starting", "Preparing sign-in.")
        await self._process("link", "--headless", timeout=AUTH_TIMEOUT, on_line=self.authorization_line)
        saved = await self.saved_status()
        if not saved.get("desired") or not saved.get("authenticated"):
            raise ConnectError("Authorization did not complete. Please retry.")
        if not saved.get("linked"):
            # T3 Code reads the link when it starts.
            self.set_state("waiting_idle", "Authorization saved. Waiting for running chats to finish before restarting T3 Code.")
            deadline = time.monotonic() + 1800
            while self.server_pid() is not None and self.active_chats():
                if time.monotonic() > deadline:
                    raise ConnectError("T3 Code is still busy. Finish running chats and choose Retry.")
                await asyncio.sleep(3)
            self.set_state("restarting", "Restarting T3 Code to activate the link. Jupyter stays open.")
            await self._stop_server()
        await self._wait_reachable()

    async def _unlink(self):
        self.set_state("disconnecting", "Disconnecting this environment.")
        await self._process("unlink")
        saved = await self.saved_status()
        if saved.get("desired") or saved.get("linked"):
            raise ConnectError("Disconnect has not completed. Retry Disconnect when the relay is reachable.")
        self.set_state("idle", "Disconnected. T3 Code still works here.")

    async def _run(self, operation):
        try:
            await operation()
        except asyncio.CancelledError:
            raise
        except TimeoutError:
            self.set_state("expired", "The request timed out or the code expired. Choose Retry for a new attempt.")
        except ConnectError as error:
            self.set_state("error", str(error))
            self.connections_url = error.connections_url
        except Exception:
            # Never expose subprocess output, HTTP errors with headers, or secrets.
            self.set_state("error", "Could not complete T3 Connect setup. Please retry.")

    async def action(self, action):
        async with self.lock:
            if action == "cancel":
                await self.close()
                with suppress(Exception):
                    await self.saved_status()
                if self.linked:
                    self.set_state("cancelled", "Setup cancelled. The approved link is kept: Retry resumes "
                                                "the setup, Disconnect revokes the link.")
                else:
                    self.set_state("idle", "Setup cancelled.")
            elif action in ("link", "retry", "disconnect"):
                if self.task and not self.task.done():
                    raise web.HTTPError(409, reason="T3 Connect is already processing a request.")
                self.set_state("starting", "Checking T3 Connect.")
                self.task = asyncio.create_task(self._run(self._unlink if action == "disconnect" else self._link))
            else:
                raise web.HTTPError(400, reason="Unknown T3 Connect action.")
        return self.snapshot()

    async def refresh(self):
        """Report a link saved in an earlier session, and recheck a ready one."""
        async with self.lock:
            if self.task and not self.task.done():
                return
            if self.state == "idle" and self.last_checked == 0:
                self.last_checked = time.time()
                with suppress(Exception):
                    saved = await self.saved_status()
                    if saved.get("desired") and saved.get("authenticated"):
                        self.task = asyncio.create_task(self._run(self._wait_reachable))
            elif self.state == "ready" and time.time() - self.last_checked > 30:
                self.task = asyncio.create_task(self._run(self._wait_reachable))

    async def close(self):
        if self.task and not self.task.done():
            self.task.cancel()
            with suppress(asyncio.CancelledError):
                await self.task
        self.task = None


class ConnectApiHandler(APIHandler):
    """The state and the actions. APIHandler checks the notebook server's
    login, and for a browser its XSRF token and origin."""

    def initialize(self, manager):
        self.manager = manager

    @web.authenticated
    async def get(self):
        self.set_header("Cache-Control", "no-store")
        await self.manager.refresh()
        self.finish(self.manager.snapshot())

    @web.authenticated
    async def post(self):
        self.set_header("Cache-Control", "no-store")
        body = self.get_json_body() or {}
        if not isinstance(body, dict) or set(body) != {"action"} or not isinstance(body["action"], str):
            raise web.HTTPError(400)
        self.finish(await self.manager.action(body["action"]))


class ConnectPageHandler(JupyterHandler):
    @web.authenticated
    def get(self):
        self.set_header("Cache-Control", "no-store")
        self.set_header("Content-Type", "text/html; charset=utf-8")
        self.set_header("Content-Security-Policy",
                        "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; "
                        "connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'self'")
        # Reading the token also sets its cookie, which the API checks the
        # page's requests against.
        self.finish(PAGE.read_text().replace("__BASE_URL__", json.dumps(self.base_url))
                    .replace("__XSRF__", json.dumps(self.xsrf_token.decode())))


def _jupyter_server_extension_points():
    return [{"module": "t3_connect"}]


def _load_jupyter_server_extension(server_app):
    manager = ConnectManager()
    base = server_app.web_app.settings["base_url"]
    server_app.web_app.add_handlers(".*$", [
        (url_path_join(base, ROUTE, "api"), ConnectApiHandler, {"manager": manager}),
        (url_path_join(base, ROUTE) + "/?", ConnectPageHandler),
    ])
    server_app.log.info("t3-connect: page at %s/ (off until the user sets it up)", url_path_join(base, ROUTE))
