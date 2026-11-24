#!/usr/bin/env python3
"""Checks T3 Connect's page and API the way a browser reaches them: through
the notebook server, under a nested URL. Called by t3-connect-smoke.sh and by
the t3-connect component's test.

    t3-connect-check.py <base url> <token>

Standard library only. It asks for the state and sends requests that must be
refused. It never asks to link: that would contact T3's account service.
"""

import json
import sys
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

BASE, TOKEN = sys.argv[1:3]
PAGE = BASE + "t3-connect/"
API = BASE + "t3-connect/api"
FAILED = 0


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *_):
        return None


opener = build_opener(NoRedirect)


def fetch(url, authenticated=True, data=None, headers=None):
    """(status, headers, body); a refusal is an answer, not an error."""
    headers = {**({"Authorization": f"token {TOKEN}"} if authenticated else {}), **(headers or {})}
    if data is not None:
        headers.setdefault("Content-Type", "application/json")
    try:
        with opener.open(Request(url, data=data, headers=headers), timeout=60) as response:
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


# The notebook server's login comes first, for the page and the API.
for url in (PAGE, API):
    status, _, _ = fetch(url, authenticated=False)
    check(status in (302, 403), f"{url.removeprefix(BASE)} needs the notebook server's login", status)
status, _, _ = fetch(API, authenticated=False, data=b'{"action": "link"}')
check(status in (302, 403), "an action needs the notebook server's login", status)

status, headers, body = fetch(PAGE)
page = body.decode(errors="replace")
check(status == 200 and "<title>T3 Connect</title>" in page
      and f"const base = {json.dumps(urlsplit(BASE).path)};" in page,
      "the page is served for this session's path", status)
check("default-src 'none'" in headers.get("Content-Security-Policy", ""),
      "the page may load nothing from elsewhere", headers.get("Content-Security-Policy"))

# Off until the user asks.
status, _, body = fetch(API)
state = json.loads(body) if status == 200 else {}
check(state.get("state") == "idle" and state.get("linked") is False and state.get("code") is None
      and state.get("needs_server") is False,
      "T3 Connect is off: idle, not linked, and it does not ask for T3 Code to be started", body[:300])

# A browser logged in to the notebook server sends its cookie with requests
# other sites make. Those cannot switch Connect on.
status, headers, _ = fetch(BASE + "lab?token=" + TOKEN, authenticated=False)
cookie = "; ".join(value.split(";", 1)[0] for value in headers.get_all("Set-Cookie") or [])
status, _, _ = fetch(API, authenticated=False, headers={"Cookie": cookie})
check(status == 200, "the browser's cookie is the login for the state", status)
for origin in ("https://elsewhere.example.org", None):
    sent = {"Cookie": cookie, **({"Origin": origin} if origin else {})}
    status, _, body = fetch(API, authenticated=False, data=b'{"action": "link"}', headers=sent)
    check(status in (403, 404), f"an action with the browser's cookie from {origin or 'a page without its token'} is refused",
          f"{status} {body[:200]}")
status, _, body = fetch(API)
check(status == 200 and json.loads(body).get("state") == "idle", "the refused requests changed nothing", body[:200])

# What the API accepts is exactly an action it knows.
for payload in (b'{"action": "format-disk"}', b'{"action": "link", "more": 1}', b'["link"]'):
    status, _, _ = fetch(API, data=payload)
    check(status == 400, f"the API refuses {payload.decode()}", status)

sys.exit(1 if FAILED else 0)
