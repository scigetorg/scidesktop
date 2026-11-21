#!/usr/bin/env python3
"""Checks a JupyterLab file viewer the way JupyterLab reaches it: through the
notebook server, under a nested URL. Called by viewer-smoke.sh and by the
viewer components' tests.

    viewer-check.py <base url> <token> <jupyterlab-niivue|jupyterlab-freebrowse>

Standard library only. It checks what JupyterLab needs to open a file in the
viewer: the extension is offered to the page, its code and the viewer's own
files are served, and a NIfTI file saved in the home comes back byte for byte,
behind the login, from the address the viewer downloads it from. (NiiVue's
server extension serves its packaged JavaScript without a login, as upstream
wrote it; that is code anyone can download from PyPI, never a user's file.) It does not
draw the image: that needs a browser.
"""

import base64
import gzip
import json
import re
import struct
import sys
from urllib.error import HTTPError
from urllib.parse import quote, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

BASE, TOKEN, VIEWER = sys.argv[1:4]
BASE_PATH = urlsplit(BASE).path
# The JupyterLab extension each component ships.
EXTENSIONS = {"jupyterlab-niivue": "@niivue/jupyter", "jupyterlab-freebrowse": "jupyterlab-freebrowse"}
FAILED = 0


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *_):
        return None


opener = build_opener(NoRedirect)


def fetch(path, authenticated=True, data=None, method=None):
    """(status, headers, body); a refusal is an answer, not an error."""
    headers = {"Authorization": f"token {TOKEN}"} if authenticated else {}
    if data is not None:
        headers["Content-Type"] = "application/json"
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


def nifti():
    """A 4x4x4 NIfTI-1 volume of 8-bit voxels, gzipped as .nii.gz files are."""
    header = bytearray(348)
    struct.pack_into("<i", header, 0, 348)
    struct.pack_into("<8h", header, 40, 3, 4, 4, 4, 1, 1, 1, 1)
    struct.pack_into("<hh", header, 70, 2, 8)
    struct.pack_into("<8f", header, 76, 1, 1, 1, 1, 1, 1, 1, 1)
    struct.pack_into("<f", header, 108, 352)
    header[344:348] = b"n+1\0"
    return gzip.compress(bytes(header) + bytes(4) + bytes(range(64)), mtime=0)


extension = EXTENSIONS[VIEWER]

# JupyterLab loads the extensions its page names.
status, _, body = fetch("lab")
config = re.search(r'<script id="jupyter-config-data" type="application/json">(.*?)</script>', body.decode(), re.S)
offered = {entry["name"]: entry for entry in json.loads(config[1])["federated_extensions"]} if config else {}
if check(extension in offered, f"JupyterLab's page offers the {extension} extension", sorted(offered) or status):
    entry = "lab/extensions/" + extension + "/static/" + offered[extension]["load"].removeprefix("static/")
    status, headers, body = fetch(entry)
    check(status == 200 and "javascript" in headers.get("Content-Type", "") and body,
          "the extension's code is served", status)

if VIEWER == "jupyterlab-freebrowse":
    # FreeBrowse is an application of its own, in a frame, at <session URL>/freebrowse/.
    status, headers, body = fetch("freebrowse/")
    page = body.decode(errors="replace")
    scripts = re.findall(r'src="\./(assets/[^"]+\.js)"', page)
    check(status == 200 and "text/html" in headers.get("Content-Type", "") and scripts,
          "FreeBrowse's page is served at freebrowse/", status)
    for script in scripts[:1]:
        status, headers, body = fetch("freebrowse/" + script)
        check(status == 200 and "javascript" in headers.get("Content-Type", "") and body,
              "FreeBrowse's page loads its code from the session's path", status)
    status, _, _ = fetch("freebrowse/", authenticated=False)
    check(status in (302, 403), "FreeBrowse needs the notebook server's login", status)
    # Only the viewer's packaged files are served there, never the home.
    status, _, _ = fetch("freebrowse/..%2F..%2F..%2F..%2Fetc%2Fpasswd")
    check(status in (403, 404), "FreeBrowse serves nothing outside its own files", status)

# The viewer opens a file by downloading it from the notebook server.
name = f"{VIEWER}-smoke.nii.gz"
volume = nifti()
status, _, body = fetch("api/contents/" + quote(name), method="PUT", data=json.dumps(
    {"type": "file", "format": "base64", "content": base64.b64encode(volume).decode()}).encode())
if check(status in (200, 201), "a NIfTI file is saved in the home", f"{status} {body[:200]}"):
    status, _, body = fetch("files/" + quote(name))
    check(status == 200 and body == volume, "the viewer's download of the file returns it unchanged", status)
    status, _, _ = fetch("files/" + quote(name), authenticated=False)
    check(status in (302, 403), "the file needs the notebook server's login", status)
    fetch("api/contents/" + quote(name), method="DELETE")

sys.exit(1 if FAILED else 0)
