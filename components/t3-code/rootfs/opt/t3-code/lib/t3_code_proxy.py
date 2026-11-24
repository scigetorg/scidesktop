"""T3 Code behind the notebook server.

Jupyter Server Proxy starts T3 on the first request (t3_code_serve.py), checks
the notebook server's login on every request and forwards it to T3 on
loopback. This module is the proxy entry and its two hooks:

- `request_headers` adds T3's own credential, so the browser never holds one.
  A request that changes something gets it only when it comes from the
  session's own pages or from a client that sent the notebook server's token.
- `rewrite_response` adapts T3's web client, which has no base-path option
  and addresses everything from the root of the origin, to the session's URL.

The rewrite is tied to the pinned client: each anchor below must occur exactly
once in its bundle. The component's test runs it over the installed client, so
a T3 release that moves an anchor fails the build, not a session.
"""

import errno
import json
import logging
import os
import re
import select
import signal
import sys
import time
from pathlib import Path

ROUTE = "t3-code"
LIB = Path(__file__).resolve().parent
SERVE = LIB / "t3_code_serve.py"
ADAPTER = LIB / "t3_code_adapter.js"
ICON = LIB / "scigent.svg"
SESSION_FILE = "jupyter-proxy-session.json"
# A component that sets up T3 Connect for this session names its page here,
# relative to the session's URL (the t3-connect component does). Without it
# T3's own Connect button is hidden: it signs in through t3.codes, which
# accepts T3's own origins only.
CONNECT_PATH = Path("/etc/scidesktop/t3-code/connect-path")

# T3 accepts connections a moment before it can serve, and answers 503 until
# then. The proxy takes any answer for readiness, so the first page can be one.
STARTING_PAGE = b"""<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta http-equiv="refresh" content="1">
<title>scigent.ai</title>
<body style="font: 1rem system-ui, sans-serif; margin: 3rem">T3 Code is starting.</body>
</html>
"""

ROUTER_ANCHOR = "context:{},defaultPreload:`intent`"
PRELOAD_ANCHOR = "return`/`+e"
FILE_URL_ANCHOR = "try{return new URL(t,e).toString()}catch{return null}"


def base_dir(environ=os.environ):
    """T3's data directory: T3CODE_HOME, or ~/.t3 as T3 itself defaults to."""
    return Path(environ.get("T3CODE_HOME") or Path.home() / ".t3").expanduser()


def _replace_once(text, anchor, replacement, what):
    if text.count(anchor) != 1:
        raise ValueError(f"T3 Code's {what} changed; update the base-path adapter in {__file__}")
    return text.replace(anchor, replacement)


def rewrite_client(body, content_type, path, prefix):
    """One response of T3's web client, adapted to live under `prefix`.

    Only the application shell, its script bundles and its stylesheets are
    changed. API payloads and files the user previews pass through as sent.
    """
    if path.startswith("/assets/") and path.endswith(".js"):
        text = body.decode("utf-8")
        if re.fullmatch(r"/assets/main-[\w-]+\.js", path):
            text = _replace_once(text, ROUTER_ANCHOR,
                                 "basepath:" + json.dumps(prefix[:-1]) + "," + ROUTER_ANCHOR, "router")
        if re.fullmatch(r"/assets/index-[\w-]+\.js", path):
            text = _replace_once(text, PRELOAD_ANCHOR, "return" + json.dumps(prefix) + "+e", "asset loader")
        if re.fullmatch(r"/assets/assets-[\w-]+\.js", path):
            text = _replace_once(
                text, FILE_URL_ANCHOR,
                "try{return window.__t3CodeTarget(new URL(t,e).toString()).url}catch{return null}",
                "file URL resolver")
        # Worker and WASM files are named by absolute URL even where script
        # imports are relative.
        text = re.sub(r'(["\'`])/assets/', lambda m: m[1] + prefix + "assets/", text)
        return text.encode()
    if content_type.split(";", 1)[0].strip() == "text/html" and not path.startswith(("/api/", "/assets/")):
        text = body.decode("utf-8")
        # Only the application shell gets the adapter. An HTML file the user
        # previews does not.
        if '<div id="root">' not in text or 'id="boot-shell"' not in text:
            return body
        text = re.sub(r'((?:src|href)=")/(?!/)', lambda m: m[1] + prefix, text)
        # A manifest is fetched without cookies unless asked, and the notebook
        # server answers nothing without them.
        text = re.sub(
            r'<link\b[^>]*\brel="manifest"[^>]*>',
            lambda m: re.sub(r'\s+crossorigin(?:="[^"]*")?', "", m[0])
            .replace("<link", '<link crossorigin="use-credentials"', 1),
            text)
        adapter = (ADAPTER.read_text()
                   .replace("__T3_CODE_PREFIX__", json.dumps(prefix).replace("<", "\\u003c"))
                   .replace("__T3_CODE_CONNECT__", json.dumps(connect_url(prefix)).replace("<", "\\u003c")))
        return _replace_once(text, "<head>", "<head><script>" + adapter + "</script>", "page shell").encode()
    if path.startswith("/assets/") and path.endswith(".css"):
        return re.sub(rb"url\(/(?!/)", b"url(" + prefix.encode(), body)
    return body


def connect_url(prefix, connect_path=CONNECT_PATH):
    """The address of the session's T3 Connect page, or None when the image has none."""
    try:
        path = connect_path.read_text().strip()
    except OSError:
        return None
    if not re.fullmatch(r"[a-z0-9-]+/", path):
        return None
    return prefix[: -len(ROUTE) - 1] + path


def _prefix():
    from jupyter_server.serverapp import ServerApp
    from jupyter_server.utils import url_path_join

    return url_path_join(ServerApp.instance().base_url, ROUTE) + "/"


def rewrite_response(response, path):
    """Jupyter Server Proxy's rewrite_response hook."""
    # T3 answers one user behind the notebook server's login: nothing of it is
    # for other origins, and its own cookies would be set for the whole host.
    for header in ("Access-Control-Allow-Origin", "Set-Cookie"):
        if header in response.headers:
            del response.headers[header]
    path = path.split("?", 1)[0]
    if response.code == 503 and not path.startswith(("/api/", "/assets/", "/.well-known/")):
        response.body = STARTING_PAGE
        response.headers["Content-Type"] = "text/html; charset=utf-8"
        response.headers["Retry-After"] = "1"
        response.headers["Cache-Control"] = "no-store"
        return
    # A HEAD request's answer has the headers of a file and none of its text.
    if response.code != 200 or not response.body:
        return
    body = rewrite_client(response.body, response.headers.get("Content-Type", ""), path, _prefix())
    if body is not response.body:
        response.body = body
        # The adapted file depends on this module as well as on T3's build, so
        # T3's validators and its one-year lifetime no longer describe it. The
        # notebook server adds an ETag of what it sends; the browser asks again
        # each time and gets 304 while that is unchanged.
        response.headers["Cache-Control"] = "no-cache"
        for header in ("ETag", "Last-Modified"):
            if header in response.headers:
                del response.headers[header]


_token = (None, "")


def _session_token():
    """The bearer token t3_code_serve.py issued when it started T3."""
    global _token
    file = base_dir() / SESSION_FILE
    try:
        stat = file.stat()
        stamp = (str(file), stat.st_ino, stat.st_mtime_ns)
        if _token[0] != stamp:
            _token = (stamp, json.loads(file.read_text())["token"])
    except (OSError, ValueError, KeyError):
        return ""
    return _token[1]


SAFE_METHODS = ("GET", "HEAD", "OPTIONS")


def _proxy_handler():
    """The request handler that is asking for these headers.

    Jupyter Server Proxy calls the hook from the handler but passes it only
    the port and base URL. Jupyter Server records the handler of the request
    it is serving in its call context when that handler's prepare() runs,
    which is before the proxy asks for headers.
    """
    from jupyter_server.base.call_context import CallContext

    handler = CallContext.get(CallContext.JUPYTER_HANDLER)
    if handler is None:
        raise RuntimeError("t3-code: no request handler is asking for the proxy's headers")
    return handler


def require_own_origin(handler):
    """Refuse a request that changes something unless the session sent it.

    Jupyter Server Proxy leaves the cross-site check to the proxied
    application, and T3 would accept the credential added below from any
    page. A browser logged in to the notebook server sends its cookie with
    requests another site makes, so such a request must name the session's
    own origin (or one the server is configured to allow), as Jupyter requires
    of a WebSocket. A client that sent the server's token is not a browser
    acting for another site.
    """
    from tornado.web import HTTPError

    request = handler.request
    if request.method in SAFE_METHODS or handler.token_authenticated:
        return
    if request.headers.get("Origin") is None or not handler.check_origin():
        raise HTTPError(403, "T3 Code accepts changes from this session's own pages only")


def request_headers():
    """Jupyter Server Proxy's request_headers_override hook.

    The notebook server has checked its own login by now. Its cookies and
    token end here: T3 gets the session issued for this proxy instead.
    """
    require_own_origin(_proxy_handler())
    token = _session_token()
    return {
        "Authorization": f"Bearer {token}" if token else "",
        "Cookie": "",
        # The rewrite needs the bodies as written.
        "Accept-Encoding": "identity",
    }


TICKET = re.compile(r"(wsTicket=)[^&\s\"']+")


def redact_tickets():
    """Keep T3's WebSocket tickets out of the notebook server's log.

    T3's client puts a short-lived ticket in the WebSocket's URL, and the
    proxy logs the URLs it connects to. Every log record passes through the
    record factory, whichever logger and handler it is for.
    """
    make = logging.getLogRecordFactory()
    if getattr(make, "redacts_t3_tickets", False):
        return

    def record_factory(*args, **kwargs):
        record = make(*args, **kwargs)
        try:
            message = record.getMessage()
        except Exception:
            return record
        if "wsTicket=" in message:
            record.msg, record.args = TICKET.sub(r"\1[redacted]", message), None
        return record

    record_factory.redacts_t3_tickets = True
    logging.setLogRecordFactory(record_factory)


def _proc_state_and_ppid(pid):
    """Return `(state, ppid)` from `/proc/<pid>/stat`, or `(None, None)`."""
    try:
        fields = Path(f"/proc/{pid}/stat").read_text().rpartition(")")[2].split()
        return fields[0], int(fields[1])
    except (OSError, IndexError, ValueError):
        return None, None


def _matches_t3_serve(pid, target_base, executable):
    """True when `pid` is a `t3 serve` process for `target_base`."""
    try:
        argv = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    except OSError:
        return False
    if len(argv) < 4 or argv[0] != executable or argv[1] != b"serve":
        return False
    return any(
        argv[i] == b"--base-dir" and argv[i + 1] == target_base
        for i in range(2, len(argv) - 1)
    )


def _open_own_t3_children(base, executable=b"/opt/t3-code/app/t3"):
    """Pin direct child `t3 serve` processes of this process for `base`.

    Only children whose PPID is `os.getpid()` are matched, so another process
    loading this config (such as `jupyter server --show-config`) never signals
    a live T3 server started by the notebook server. Where supported, each
    child is pinned with `os.pidfd_open` before re-verifying `/proc` so a
    recycled PID cannot be signaled.
    """
    my_pid = os.getpid()
    target = str(base).encode()
    if isinstance(executable, str):
        executable = executable.encode()
    pinned = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        state, ppid = _proc_state_and_ppid(pid)
        if ppid != my_pid or state in (None, "Z"):
            continue
        pidfd = None
        if hasattr(os, "pidfd_open"):
            try:
                pidfd = os.pidfd_open(pid, 0)
            except OSError as error:
                if error.errno not in (errno.ENOSYS, errno.EPERM):
                    continue
        # Re-verify after pinning the pidfd so a PID recycled before pidfd_open
        # is discarded immediately.
        state, ppid = _proc_state_and_ppid(pid)
        if ppid != my_pid or state in (None, "Z") or not _matches_t3_serve(pid, target, executable):
            if pidfd is not None:
                os.close(pidfd)
            continue
        pinned.append((pid, pidfd))
    return pinned


def stop_server(seconds=20, base=None, executable=b"/opt/t3-code/app/t3"):
    """Stop this process's child T3 Code server and wait for it to close its state.

    Registered with atexit by jupyter_server_config.d/t3-code.py: simpervisor
    forwards SIGTERM without waiting, and the container ends as soon as the
    notebook server exits. Waiting here keeps T3 from being SIGKILLed while
    stopping child provider servers (such as opencode serve) and checkpointing
    its SQLite WAL.
    """
    pinned = _open_own_t3_children(base_dir() if base is None else base, executable=executable)
    if not pinned:
        return
    try:
        for pid, pidfd in pinned:
            try:
                if pidfd is not None and hasattr(signal, "pidfd_send_signal"):
                    signal.pidfd_send_signal(pidfd, signal.SIGTERM)
                else:
                    os.kill(pid, signal.SIGTERM)
            except OSError:
                pass
        deadline = time.monotonic() + seconds
        pidfd_list = [fd for _, fd in pinned if fd is not None]
        fallback_pids = [pid for pid, fd in pinned if fd is None]
        while (pidfd_list or fallback_pids) and time.monotonic() < deadline:
            remaining = max(0.0, deadline - time.monotonic())
            if pidfd_list:
                timeout = min(remaining, 0.1) if fallback_pids else remaining
                ready, _, _ = select.select(pidfd_list, [], [], timeout)
                if ready:
                    ready_set = set(ready)
                    pidfd_list = [fd for fd in pidfd_list if fd not in ready_set]
            elif fallback_pids:
                time.sleep(min(remaining, 0.1))
            if fallback_pids:
                fallback_pids = [
                    pid for pid in fallback_pids
                    if _proc_state_and_ppid(pid)[0] not in (None, "Z")
                ]
    finally:
        for _, pidfd in pinned:
            if pidfd is not None:
                try:
                    os.close(pidfd)
                except OSError:
                    pass


def server_entry():
    """The `c.ServerProxy.servers` entry: T3 Code at <session URL>/t3-code/."""
    return {
        "command": [sys.executable, str(SERVE), "{port}"],
        "timeout": 120,
        "request_headers_override": request_headers,
        "rewrite_response": rewrite_response,
        "new_browser_tab": False,
        "launcher_entry": {
            "enabled": True,
            "title": "scigent.ai",
            "icon_path": str(ICON),
            "category": "Scidesktop",
        },
    }
