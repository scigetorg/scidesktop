"""App mode: start one desktop application and show the desktop stream.

    desktop_app.py <port> <desktop_url> <desktop_file>

Spawned by jupyter-server-proxy on the first click of the application's
launcher tile (see jupyter_server_config.py). The tile opens <name>/launch;
any other path answers 200 and does nothing, which is what the proxy's
readiness check (GET /) sees. Each launch request:

1. starts the desktop session if it is not running (start_desktop.sh) and
   waits until a window manager manages the display;
2. runs the application's Exec line from <desktop_file>, unless the copy it
   started earlier is still running;
3. maximises and activates the application's first window, through EWMH, so
   it works under any compliant window manager;
4. answers with a page that shows the desktop stream in a tab named
   "scidesktop-desktop" (reused by later clicks) and closes itself.

Runs on Selkies' interpreter, which carries python-xlib.
"""
import configparser
import html
import http.server
import json
import os
import shlex
import socket
import subprocess
import sys
import threading
import time

import selkies

sys.path.insert(0, os.path.dirname(selkies.__file__))
from Xlib import X, display as xdisplay  # noqa: E402
from Xlib.protocol import event as xevent  # noqa: E402

PORT = int(sys.argv[1])
DESKTOP_URL = sys.argv[2]
DESKTOP_FILE = sys.argv[3]
DISPLAY = os.environ.setdefault("DISPLAY", ":20")
X_SOCKET = f"/tmp/.X11-unix/X{DISPLAY.split(':', 1)[1].split('.')[0]}"
RUNTIME_DIR = os.environ.setdefault("XDG_RUNTIME_DIR", f"/tmp/runtime-{os.getuid()}")
# Written by start_desktop.sh: the session's D-Bus and PulseAudio addresses.
SESSION_ENV = os.path.join(RUNTIME_DIR, "desktop.env")
APP_ID = os.path.splitext(os.path.basename(DESKTOP_FILE))[0]
LOG = f"/tmp/desktop-app-{APP_ID}.log"
# A container image may need pulling or unpacking before its first window.
WINDOW_WAIT_S = 120

state = {"proc": None, "windows": []}
lock = threading.Lock()


def log(msg):
    print(f"[desktop-app {APP_ID}] {msg}", flush=True)


def exec_line():
    """The Exec command with desktop-entry field codes (%f, %U, ...) removed."""
    entry = configparser.ConfigParser(interpolation=None, strict=False)
    entry.optionxform = str
    entry.read(DESKTOP_FILE)
    argv = shlex.split(entry["Desktop Entry"]["Exec"])
    return [a.replace("%%", "%") for a in argv if not (len(a) == 2 and a[0] == "%")]


def wait_for(test, timeout, step=0.05):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if test():
            return True
        time.sleep(step)
    return test()


def x_alive():
    """An X server answers; a container restart leaves its socket file behind."""
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        try:
            s.connect(X_SOCKET)
            return True
        except OSError:
            return False


def ensure_session():
    if not x_alive():
        log("starting desktop session")
        with open("/tmp/scidesktop-desktop.log", "ab") as out:
            subprocess.Popen(["/opt/scidesktop/start_desktop.sh"], stdin=subprocess.DEVNULL,
                             stdout=out, stderr=out, start_new_session=True)
    if not wait_for(x_alive, 30):
        raise RuntimeError(f"no X server at {X_SOCKET}")
    d = xdisplay.Display(DISPLAY)
    try:
        root = d.screen().root
        check = d.intern_atom("_NET_SUPPORTING_WM_CHECK")
        # A window started before the window manager is never maximised.
        if not wait_for(lambda: root.get_full_property(check, X.AnyPropertyType), 30):
            raise RuntimeError("no window manager on the display")
    finally:
        d.close()
    wait_for(lambda: os.path.exists(SESSION_ENV), 5)


def session_env():
    env = dict(os.environ)
    try:
        with open(SESSION_ENV) as f:
            env.update(line.rstrip("\n").split("=", 1) for line in f if "=" in line)
    except OSError:
        log(f"no {SESSION_ENV}; the application gets no session bus or audio")
    return env


def client_list(d):
    prop = d.screen().root.get_full_property(d.intern_atom("_NET_CLIENT_LIST"), X.AnyPropertyType)
    return list(prop.value) if prop else []


def send_root_message(d, window, atom, data):
    root = d.screen().root
    ev = xevent.ClientMessage(window=window, client_type=d.intern_atom(atom),
                              data=(32, (data + [0] * 5)[:5]))
    root.send_event(ev, event_mask=X.SubstructureRedirectMask | X.SubstructureNotifyMask)


def activate(d, wid):
    # Source 2: a pager or taskbar, which window managers obey without focus
    # stealing prevention.
    send_root_message(d, d.create_resource_object("window", wid), "_NET_ACTIVE_WINDOW",
                      [2, X.CurrentTime, 0])


def maximise(d, wid):
    send_root_message(d, d.create_resource_object("window", wid), "_NET_WM_STATE",
                      [1, d.intern_atom("_NET_WM_STATE_MAXIMIZED_VERT"),
                       d.intern_atom("_NET_WM_STATE_MAXIMIZED_HORZ"), 2])


def is_main_window(d, wid):
    """A normal, top-level window: not a dialog, splash or transient."""
    w = d.create_resource_object("window", wid)
    if w.get_wm_transient_for():
        return False
    types = w.get_full_property(d.intern_atom("_NET_WM_WINDOW_TYPE"), X.AnyPropertyType)
    return not types or d.intern_atom("_NET_WM_WINDOW_TYPE_NORMAL") in types.value


def session_of(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            return int(f.read().rsplit(")", 1)[1].split()[3])
    except (OSError, IndexError, ValueError):
        return None


def is_ours(d, wid, proc):
    """The window belongs to the launched process: its _NET_WM_PID is in the
    session the launch started. A window without a PID (some X11 tools)
    is taken as ours."""
    pid = d.create_resource_object("window", wid).get_full_property(
        d.intern_atom("_NET_WM_PID"), X.AnyPropertyType)
    return not pid or session_of(pid.value[0]) == proc.pid


def watch_for_window(before):
    """Maximise and raise the first main window the launched process shows."""
    d = xdisplay.Display(DISPLAY)
    try:
        end = time.monotonic() + WINDOW_WAIT_S
        while time.monotonic() < end:
            proc = state["proc"]
            new = [w for w in client_list(d) if w not in before]
            main = [w for w in new if is_main_window(d, w) and is_ours(d, w, proc)]
            if main:
                wid = main[0]
                maximise(d, wid)
                activate(d, wid)
                d.flush()
                state["windows"] = main
                log(f"window 0x{wid:x} maximised")
                return
            if proc is not None and proc.poll() is not None and not new:
                log(f"exited with {proc.returncode} before showing a window; see {LOG}")
                return
            time.sleep(0.1)
        log(f"no window within {WINDOW_WAIT_S} s")
    finally:
        d.close()


def launch_or_raise():
    with lock:
        ensure_session()
        proc = state["proc"]
        if proc is not None and proc.poll() is None:
            d = xdisplay.Display(DISPLAY)
            try:
                alive = [w for w in state["windows"] if w in client_list(d)]
                if alive:
                    activate(d, alive[0])
                    d.flush()
            finally:
                d.close()
            return "raised"
        d = xdisplay.Display(DISPLAY)
        try:
            before = set(client_list(d))
        finally:
            d.close()
        argv = exec_line()
        log(f"running {argv}")
        out = open(LOG, "ab")
        state["proc"] = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=out, stderr=out,
                                         start_new_session=True, cwd=os.path.expanduser("~"),
                                         env=session_env())
        state["windows"] = []
        threading.Thread(target=watch_for_window, args=(before,), daemon=True).start()
        return "started"


PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>{title}</title></head>
<body style="font-family:sans-serif">
<p>{message} <a id="go" href="{url}" target="scidesktop-desktop">Open the desktop</a></p>
<script>
// Show the stream in one named tab: a later click reuses it rather than
// opening a second stream. Without that tab, and with pop-ups blocked (no
// user gesture on this page), this tab becomes it.
var url = {url_js};
var w = null;
try {{ w = window.open("", "scidesktop-desktop"); }} catch (e) {{}}
if (w) {{
  var current = "";
  try {{ current = w.location.href; }} catch (e) {{}}
  if (current.indexOf(url) === -1) w.location.replace(url);
  w.focus();
  window.close();
}} else {{
  window.name = "scidesktop-desktop";
  location.replace(url);
}}
</script></body></html>
"""


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.split("?")[0].rstrip("/") != "/launch":
            self.send_response(200)
            self.end_headers()
            return
        try:
            result = launch_or_raise()
            message, status = f"{APP_ID}: {result}.", 200
        except Exception as e:  # reported to the browser, which has no other channel
            log(f"failed: {e}")
            message, status = f"{APP_ID} failed to start: {e}.", 500
        body = PAGE.format(title=html.escape(APP_ID), message=html.escape(message),
                           url=html.escape(DESKTOP_URL), url_js=json.dumps(DESKTOP_URL).replace("</", "<\\/"))
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body.encode())

    def log_message(self, fmt, *args):
        log(fmt % args)


if __name__ == "__main__":
    log(f"listening on 127.0.0.1:{PORT} for {DESKTOP_FILE}")
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
