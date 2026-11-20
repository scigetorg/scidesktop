#!/usr/bin/env python3
"""Checks T3 Code the way its user reaches it: through the notebook server,
under a nested URL. Called by t3-code-smoke.sh and by the t3-code component's
test.

    t3-code-check.py <base url> <token>

Runs with Jupyter's Python, which has the websocket client. No request goes
to a model provider and none carries a provider credential.
"""

import json
import re
import sys
import time
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

import websocket

BASE, TOKEN = sys.argv[1:3]
PREFIX = urlsplit(BASE).path + "t3-code/"
T3 = BASE + "t3-code/"
FAILED = 0


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *_):
        return None


opener = build_opener(NoRedirect)


def fetch(url, authenticated=True, data=None):
    """(status, headers, body); a refusal is an answer, not an error."""
    headers = {"Authorization": f"token {TOKEN}"} if authenticated else {}
    try:
        with opener.open(Request(url, data=data, headers=headers), timeout=150) as response:
            return response.status, response.headers, response.read()
    except HTTPError as error:
        return error.code, error.headers, error.read()


def check(passed, message, detail=""):
    global FAILED
    if passed:
        print(f"  ok    {message}")
    else:
        FAILED += 1
        print(f"  FAIL  {message}{': ' + str(detail)[:300] if detail != '' else ''}")
    return passed


def finish():
    sys.exit(1 if FAILED else 0)


# The tile JupyterLab's launcher draws.
status, _, body = fetch(BASE + "server-proxy/servers-info")
tiles = {entry["name"]: entry for entry in json.loads(body)["server_processes"]} if status == 200 else {}
tile = tiles.get("t3-code", {})
check(tile.get("launcher_entry", {}).get("title") == "scigent.ai" and tile["launcher_entry"]["enabled"]
      and tile.get("new_browser_tab") is False,
      "the launcher has a scigent.ai tile that opens in JupyterLab", tile or status)
status, headers, body = fetch(BASE + "server-proxy/icon/t3-code")
check(status == 200 and b"<svg" in body, "the tile's icon is served", status)

# The notebook server's login comes first, for pages, API calls and sockets.
for path in ("", "api/auth/session", "assets/x.js"):
    status, _, _ = fetch(T3 + path, authenticated=False)
    check(status in (302, 403), f"t3-code/{path} needs the notebook server's login", status)
status, _, _ = fetch(T3 + "api/auth/websocket-ticket", authenticated=False, data=b"")
check(status in (302, 403), "a POST needs the notebook server's login", status)
try:
    websocket.create_connection(T3.replace("http", "ws", 1) + "ws", timeout=20).close()
    check(False, "a WebSocket needs the notebook server's login", "it connected")
except websocket.WebSocketBadStatusException as error:
    check(error.status_code in (302, 403), "a WebSocket needs the notebook server's login", error.status_code)

# The first request starts T3. T3 answers 503 for a moment before it can
# serve; a browser then gets a page that reloads itself.
started = time.monotonic()
status, headers, body = fetch(T3)
while status == 503 and time.monotonic() - started < 120:
    if b"T3 Code is starting" not in body or headers.get("Retry-After") != "1":
        break
    time.sleep(0.5)
    status, headers, body = fetch(T3)
shell = body.decode(errors="replace")
if not check(status == 200 and '<div id="root">' in shell, "T3 Code starts and serves its page", f"{status} {shell}"):
    finish()
print(f"        (first answer after {time.monotonic() - started:.1f} s)")
check("window.__t3CodeTarget" in shell and f"const prefix = {json.dumps(PREFIX)}" in shell,
      "the page carries the adapter for this session's path")
local = re.findall(r'(?:src|href)="(/(?!/)[^"]*)"', shell)
check(local and all(url.startswith(PREFIX) for url in local),
      "everything the page loads is under the session's path", local)
entry = re.search(r'src="(' + re.escape(PREFIX) + r'assets/index-[\w-]+\.js)"', shell)
if not check(entry is not None, "the page loads its entry script from the session's path"):
    finish()

origin = BASE[: len(BASE) - len(urlsplit(BASE).path)]
status, headers, body = fetch(origin + entry[1])
script = body.decode(errors="replace")
check(status == 200 and "javascript" in headers.get("Content-Type", "")
      and f"return{json.dumps(PREFIX)}+e" in script,
      "the entry script preloads from the session's path", status)
main = re.search(r"main-[\w-]+\.js", script)
if check(main is not None, "the entry script names the application bundle"):
    status, headers, body = fetch(T3 + "assets/" + main[0])
    check(status == 200 and f"basepath:{json.dumps(PREFIX[:-1])},".encode() in body,
          "the application's router is based at the session's path", status)
    check(headers.get("Cache-Control") == "no-cache",
          "the browser revalidates an adapted bundle", headers.get("Cache-Control"))
status, headers, body = fetch(T3 + "manifest.webmanifest")
check(status == 200, "the web manifest is served", status)

# The proxy signs in to T3; the browser holds no T3 credential.
status, headers, body = fetch(T3 + "api/auth/session")
session = json.loads(body) if status == 200 else {}
check(session.get("authenticated") is True and session.get("sessionMethod") == "bearer-access-token",
      "T3 accepts the proxy's own session", body[:200])
cookies = [cookie.split("=", 1)[0] for cookie in headers.get_all("Set-Cookie") or []]
check(not any(name.startswith("t3_") for name in cookies) and headers.get("Access-Control-Allow-Origin") is None,
      "T3 sets no cookie and offers nothing to other origins",
      f"{cookies} {headers.get('Access-Control-Allow-Origin')}")

status, _, body = fetch(T3 + ".well-known/t3/environment")
environment = json.loads(body) if status == 200 else {}
check(bool(environment.get("serverVersion")), f"T3 Code {environment.get('serverVersion')} answers", status)

status, _, body = fetch(T3 + "api/auth/websocket-ticket", data=b"")
if check(status == 200, "T3 issues a WebSocket ticket", f"{status} {body[:200]}"):
    url = (T3.replace("http", "ws", 1) + "ws?wsTicket=" + json.loads(body)["ticket"]
           + f"&orchestrationProtocol={environment.get('orchestrationProtocolVersion')}")
    try:
        socket = websocket.create_connection(url, header=[f"Authorization: token {TOKEN}"], timeout=30)
        # The notebook server accepts the socket before it has reached T3,
        # and closes it if T3 refuses. A socket still open and silent after
        # three seconds is one T3 holds.
        socket.settimeout(3)
        try:
            closed = socket.recv() is None
        except websocket.WebSocketTimeoutException:
            closed = False
        except websocket.WebSocketConnectionClosedException:
            closed = True
        check(not closed, "a WebSocket reaches T3 through the notebook server", "T3 closed it")
        socket.close()
    except (OSError, websocket.WebSocketException) as error:
        check(False, "a WebSocket reaches T3 through the notebook server", error)

finish()
