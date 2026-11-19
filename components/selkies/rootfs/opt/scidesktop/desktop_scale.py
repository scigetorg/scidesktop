"""Keep IceWM's sizes in step with the desktop DPI.

Selkies sets the X resource Xft.dpi from the browser's device pixel ratio
(192 on a 2x display, where the desktop is streamed at physical pixels).
Fonts sized in points follow it once IceWM reloads; IceWM's pixel sizes (the
taskbar icons, which set the taskbar's height) do not. On each DPI change this
writes IceWM's prefoverride with those sizes scaled to the DPI and restarts
IceWM, which keeps its windows.

IceWM loads only the first prefoverride it finds, from ICEWM_PRIVCFG, so that
points at a runtime folder holding the scaled copy, with links to the user's
own IceWM files (~/.icewm or $XDG_CONFIG_HOME/icewm) beside it. A user's
prefoverride, if present, is the one that gets scaled.

Usage (start_desktop.sh): desktop_scale.py setup   before IceWM starts
                          desktop_scale.py watch   once it runs
"""
import os
import re
import subprocess
import sys
import time

BASE_DPI = 96
DPI_RANGE = (48, 480)  # anything else in Xft.dpi is ignored
SYSTEM_OVERRIDE = "/etc/X11/icewm/prefoverride"
# Where IceWM finds settings when the prefoverride does not set them.
SYSTEM_PREFERENCES = ("/etc/X11/icewm/preferences", "/usr/share/icewm/preferences")
# Pixel settings scaled with the DPI, and IceWM's own default for each.
SCALED = {"SmallIconSize": 16}
# IceWM's files in its private folder. Each is linked to the user's folder
# whether it exists or not, so a file the user (or IceWM) creates during the
# session is found, and what IceWM writes lands in the home.
ICEWM_FILES = ("preferences", "theme", "keys", "menu", "toolbar", "winoptions", "programs",
               "startup", "shutdown", "restart", "focus_mode", "icons", "themes", "sounds")
SETTLE_S = 0.3  # Selkies merges the DPI and cursor size one after the other
RESTART_TIMEOUT_S = 10


def log(msg):
    print(f"[desktop] {msg}", flush=True)


def privcfg():
    return os.environ["ICEWM_PRIVCFG"]


def user_dir():
    xdg = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "icewm")
    return xdg if os.path.isdir(xdg) else os.path.expanduser("~/.icewm")


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return None


def setting(text, key):
    """The last value IceWM would take for key: indented, quoted or not."""
    found = re.findall(rf'^\s*{key}\s*=\s*"?(\d+)"?', text or "", re.M)
    return int(found[-1]) if found else None


def write(dpi):
    """Write the prefoverride for this DPI and link the user's other files."""
    out, src = privcfg(), user_dir()
    os.makedirs(out, exist_ok=True)
    os.makedirs(src, exist_ok=True)
    # Links from an earlier session may point at a folder since moved.
    for name in os.listdir(out):
        if os.path.islink(os.path.join(out, name)):
            os.unlink(os.path.join(out, name))
    for name in set(ICEWM_FILES) | set(os.listdir(src)):
        link = os.path.join(out, name)
        if name != "prefoverride" and not name.startswith(".") and not os.path.lexists(link):
            os.symlink(os.path.join(src, name), link)
    user = read(os.path.join(src, "prefoverride"))
    text = user if user is not None else read(SYSTEM_OVERRIDE) or ""
    lines = []
    if dpi != BASE_DPI:  # at 96 DPI the file is the user's (or the system's) as it is
        lines.append(f"\n# Scaled for {dpi} DPI by desktop_scale.py; later lines win.")
        prefs = read(os.path.join(src, "preferences"))
        if prefs is None:
            prefs = next((t for t in map(read, SYSTEM_PREFERENCES) if t is not None), "")
        for key, default in SCALED.items():
            base = setting(text, key) or setting(prefs, key) or default
            lines.append(f"{key}={max(16, min(128, round(base * dpi / BASE_DPI)))}")
    tmp = os.path.join(out, ".prefoverride.tmp")
    with open(tmp, "w") as f:
        f.write(text.rstrip("\n") + "\n" + "\n".join(lines) + ("\n" if lines else ""))
    os.replace(tmp, os.path.join(out, "prefoverride"))


def watch():
    import selkies
    sys.path.insert(0, os.path.dirname(selkies.__file__))
    from Xlib import X, Xatom, display as xdisplay

    d = xdisplay.Display()
    root = d.screen().root
    resources = d.intern_atom("RESOURCE_MANAGER")
    wm_check = d.intern_atom("_NET_SUPPORTING_WM_CHECK")
    root.change_attributes(event_mask=X.PropertyChangeMask)

    def current_dpi(last):
        """Xft.dpi as set; the last good value when it is missing or invalid."""
        prop = root.get_full_property(resources, Xatom.STRING)
        text = prop.value.decode(errors="replace") if prop and isinstance(prop.value, bytes) else ""
        found = re.findall(r"^Xft\.dpi:\s*(\S+)", text, re.M)
        try:
            dpi = round(float(found[-1]))
        except (IndexError, ValueError, OverflowError):
            return last
        return dpi if DPI_RANGE[0] <= dpi <= DPI_RANGE[1] else last

    def apply(dpi):
        # `icewm --restart` with no window manager running becomes one and
        # never returns: wait for IceWM to manage the display first.
        end = time.monotonic() + RESTART_TIMEOUT_S
        while not root.get_full_property(wm_check, X.AnyPropertyType):
            if time.monotonic() > end:
                log(f"no window manager; IceWM not rescaled for {dpi} DPI")
                return False
            time.sleep(0.1)
        try:
            write(dpi)
            rc = subprocess.run(["icewm", "--restart"], timeout=RESTART_TIMEOUT_S).returncode
        except (OSError, subprocess.SubprocessError) as e:
            log(f"IceWM not rescaled for {dpi} DPI: {e}")
            return False
        if rc != 0:
            log(f"icewm --restart exited with {rc}")
            return False
        log(f"IceWM rescaled for {dpi} DPI")
        return True

    applied = BASE_DPI
    dpi = current_dpi(applied)
    if dpi != applied and apply(dpi):  # the DPI changed while the session started
        applied = dpi
    while True:
        e = d.next_event()
        if e.type != X.PropertyNotify or e.atom != resources:
            continue
        time.sleep(SETTLE_S)
        while d.pending_events():
            d.next_event()
        dpi = current_dpi(applied)
        if dpi != applied and apply(dpi):
            applied = dpi


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "setup":
        write(BASE_DPI)
    elif mode == "watch":
        watch()
    else:
        sys.exit(__doc__)
