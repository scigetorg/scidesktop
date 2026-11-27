#!/usr/bin/env python3
"""Checks jupyterlab-scigethelpers the way JupyterLab reaches it: through the
notebook server under a nested base_url. Called by the component's test.sh and
by test/jupyterlab-scigethelpers-smoke.sh.

    jupyterlab-scigethelpers-check.py <base url> <token>

Standard library only. Verifies:
- federated extension & settings schema are served by JupyterLab
- unauthenticated requests are refused
- cookie-authenticated same-origin POST with X-XSRFToken succeeds (real browser path)
- cookie-authenticated cross-origin / missing-Origin POSTs (even with valid XSRF) are refused
- GET /scigethelpers/api/overview returns local state with Cache-Control: no-store
- POST /scigethelpers/api/info, /check, /cite honor allowlists, reject bad input,
  reject oversized bodies, enforce server-side overwrite confirmation, and
  compute root_dir-relative paths accurately.
"""

import json
import re
import sys
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

BASE, TOKEN = sys.argv[1:3]
PARSED_BASE = urlsplit(BASE)
SAME_ORIGIN = f"{PARSED_BASE.scheme}://{PARSED_BASE.netloc}"
FAILED = 0


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *_):
        return None


opener = build_opener(NoRedirect)


def fetch(path, authenticated=True, data=None, headers=None, method=None):
    headers = {**({"Authorization": f"token {TOKEN}"} if authenticated else {}), **(headers or {})}
    if data is not None:
        headers.setdefault("Content-Type", "application/json")
    try:
        with opener.open(Request(BASE + path, data=data, headers=headers, method=method), timeout=60) as response:
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


def parse_cookies(headers):
    jar = {}
    for value in headers.get_all("Set-Cookie") or []:
        pair = value.split(";", 1)[0]
        if "=" in pair:
            k, v = pair.split("=", 1)
            jar[k.strip()] = v.strip()
    return jar


# 1. JupyterLab page offers the federated extension and serves its JS & schema.
status, _, body = fetch("lab")
config = re.search(r'<script id="jupyter-config-data" type="application/json">(.*?)</script>', body.decode(), re.S)
offered = {entry["name"]: entry for entry in json.loads(config[1])["federated_extensions"]} if config else {}
if check("jupyterlab-scigethelpers" in offered, "JupyterLab offers jupyterlab-scigethelpers", sorted(offered) or status):
    entry = "lab/extensions/jupyterlab-scigethelpers/static/" + offered["jupyterlab-scigethelpers"]["load"].removeprefix("static/")
    st, hdrs, code = fetch(entry)
    check(st == 200 and "javascript" in hdrs.get("Content-Type", "") and code, "extension bundle is served", st)

st, _, schema_body = fetch("lab/api/settings/jupyterlab-scigethelpers:plugin")
schema_json = json.loads(schema_body) if st == 200 else {}
check(st == 200 and "showOnStartup" in (schema_json.get("schema") or {}).get("properties", {}),
      "settings schema exposes showOnStartup", st)

# 2. Unauthenticated requests are rejected on every endpoint.
for ep, payload in (
    ("scigethelpers/api/overview", None),
    ("scigethelpers/api/info", b"{}"),
    ("scigethelpers/api/check", b"{}"),
    ("scigethelpers/api/cite", b'{"action": "generate"}'),
):
    st, _, _ = fetch(ep, authenticated=False, data=payload)
    check(st in (302, 403), f"{ep} requires authentication", st)

# 3. GET /overview returns fast local state (no live probes) + Cache-Control: no-store.
st, hdrs, body = fetch("scigethelpers/api/overview")
overview = json.loads(body) if st == 200 else {}
check(st == 200 and "no-store" in hdrs.get("Cache-Control", ""),
      "GET /overview succeeds with Cache-Control: no-store", f"{st} {hdrs.get('Cache-Control')}")
check(isinstance(overview.get("info"), dict)
      and overview["info"].get("gpu", {}).get("probed") is False
      and overview["info"].get("cvmfs", {}).get("probed") is False,
      "GET /overview does not run live GPU or CVMFS probes", overview.get("info"))
check(isinstance(overview.get("container_kernels"), list) and isinstance(overview.get("uv_kernels"), list),
      "GET /overview lists container and uv kernels", overview)

# 4. Real browser cookie flow: authenticate via /lab?token=..., fetch _xsrf
# cookie, verify same-origin cookie POST + X-XSRFToken succeeds, and verify
# cross-origin / missing-Origin cookie POSTs are refused EVEN with valid XSRF.
jar = {}
st, hdrs, _ = fetch("lab?token=" + TOKEN, authenticated=False)
jar.update(parse_cookies(hdrs))
cookie_hdr = "; ".join(f"{k}={v}" for k, v in jar.items())
# Follow through to /lab with cookie to ensure _xsrf cookie is issued.
st, hdrs2, _ = fetch("lab", authenticated=False, headers={"Cookie": cookie_hdr})
jar.update(parse_cookies(hdrs2))
cookie_hdr = "; ".join(f"{k}={v}" for k, v in jar.items())
xsrf = jar.get("_xsrf", "")

st, _, _ = fetch("scigethelpers/api/overview", authenticated=False, headers={"Cookie": cookie_hdr})
check(st == 200, "browser cookie authenticates GET /overview", st)

if check(bool(xsrf), "browser login issued _xsrf cookie", list(jar)):
    st, _, resp = fetch(
        "scigethelpers/api/check",
        authenticated=False,
        data=b'{"checks": ["gpu", "t3"]}',
        headers={"Cookie": cookie_hdr, "X-XSRFToken": xsrf, "Origin": SAME_ORIGIN},
    )
    check(st == 200 and json.loads(resp).get("ok") is True,
          "same-origin browser cookie POST with X-XSRFToken succeeds", f"{st} {resp[:200]}")

    for origin in ("https://elsewhere.example.org", None):
        sent = {"Cookie": cookie_hdr, "X-XSRFToken": xsrf, **({"Origin": origin} if origin else {})}
        st, _, resp = fetch("scigethelpers/api/check", authenticated=False, data=b'{"checks": ["gpu"]}', headers=sent)
        check(st in (403, 404),
              f"cookie POST /check with valid XSRF from {origin or 'missing Origin'} is refused",
              f"{st} {resp[:200]}")

# 5. POST /info runs live probes and rejects unknown keys.
st, _, body = fetch("scigethelpers/api/info", data=b"{}")
info = json.loads(body) if st == 200 else {}
check(st == 200 and info.get("gpu", {}).get("probed") is True, "POST /info returns probed environment info", st)
st, _, _ = fetch("scigethelpers/api/info", data=b'{"unexpected": true}')
check(st == 400, "POST /info rejects unknown fields", st)

# 6. POST /check validates check names and rejects oversized / invalid payloads.
st, _, body = fetch("scigethelpers/api/check", data=b'{"checks": ["gpu", "t3"]}')
chk = json.loads(body) if st == 200 else {}
check(st == 200 and chk.get("ok") is True and [c["name"] for c in chk.get("checks", [])] == ["gpu", "t3"],
      "POST /check runs allowlisted checks and returns JSON", f"{st} {body[:200]}")
for bad in (b'{"checks": ["rm -rf /"]}', b'{"checks": "gpu"}', b'{"extra": 1}', b'["gpu"]'):
    st, _, _ = fetch("scigethelpers/api/check", data=bad)
    check(st == 400, f"POST /check refuses {bad.decode()}", st)
st, _, _ = fetch("scigethelpers/api/check", data=b'{"checks": ["' + b"a" * 20000 + b'"]}')
check(st == 413, "POST /check rejects oversized request body", st)

# 7. POST /cite enforces fixed output policy, overwrite guard, and returns relative_path.
for bad in (
    b'{"output": "/tmp/evil.md"}',
    b'{"action": "clear"}',
    b'{"action": "generate", "overwrite": "yes"}',
    b'{"url": "http://169.254.169.254"}',
):
    st, _, _ = fetch("scigethelpers/api/cite", data=bad)
    check(st == 400, f"POST /cite refuses {bad.decode()}", st)
st, _, body = fetch("scigethelpers/api/cite", data=b'{"action": "generate"}')
cite = json.loads(body) if st in (200, 409) else {}
if (overview.get("citations") or {}).get("load_count", 0) > 0:
    check(st == 200 and cite.get("ok") is True and cite.get("relative_path") == "CITATIONS.md",
          "POST /cite writes CITATIONS.md and returns relative_path", f"{st} {body[:200]}")
    # A second call without overwrite=true MUST be refused with 409 + needs_overwrite.
    st2, _, body2 = fetch("scigethelpers/api/cite", data=b'{"action": "generate"}')
    cite2 = json.loads(body2) if st2 == 409 else {}
    check(st2 == 409 and cite2.get("needs_overwrite") is True,
          "POST /cite refuses silent overwrite without overwrite=true", f"{st2} {body2[:200]}")
    # Explicit overwrite=true succeeds.
    st3, _, body3 = fetch("scigethelpers/api/cite", data=b'{"action": "generate", "overwrite": true}')
    cite3 = json.loads(body3) if st3 == 200 else {}
    check(st3 == 200 and cite3.get("ok") is True and cite3.get("relative_path") == "CITATIONS.md",
          "POST /cite overwrites when overwrite=true is supplied", f"{st3} {body3[:200]}")
else:
    check(st == 200 and cite.get("ok") is False,
          "POST /cite reports cleanly when no module loads are recorded", f"{st} {body[:200]}")

sys.exit(1 if FAILED else 0)
