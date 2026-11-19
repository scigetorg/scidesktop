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
SYSTEM_OVERRIDE = "/etc/X11/icewm/prefoverride"
# Pixel settings scaled with the DPI, and their value when the file has none.
SCALED = {"SmallIconSize": 32}
SETTLE_S = 0.3  # Selkies merges the DPI and cursor size one after the other


def privcfg():
    return os.environ["ICEWM_PRIVCFG"]


def user_dir():
    xdg = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "icewm")
    return xdg if os.path.isdir(xdg) else os.path.expanduser("~/.icewm")


def write(dpi):
    """Write the prefoverride for this DPI and link the user's other files."""
    out, src = privcfg(), user_dir()
    os.makedirs(out, exist_ok=True)
    names = os.listdir(src) if os.path.isdir(src) else []
    for name in names:
        link = os.path.join(out, name)
        if name != "prefoverride" and not os.path.lexists(link):
            os.symlink(os.path.join(src, name), link)
    template = os.path.join(src, "prefoverride") if "prefoverride" in names else SYSTEM_OVERRIDE
    try:
        with open(template) as f:
            text = f.read()
    except OSError:
        text = ""
    lines = [f"\n# Scaled for {dpi} DPI by desktop_scale.py; later lines win."]
    for key, default in SCALED.items():
        found = re.findall(rf"^{key}\s*=\s*(\d+)", text, re.M)
        base = int(found[-1]) if found else default
        lines.append(f"{key}={max(16, min(128, round(base * dpi / BASE_DPI)))}")
    tmp = os.path.join(out, ".prefoverride.tmp")
    with open(tmp, "w") as f:
        f.write(text.rstrip("\n") + "\n" + "\n".join(lines) + "\n")
    os.replace(tmp, os.path.join(out, "prefoverride"))


def watch():
    import selkies
    sys.path.insert(0, os.path.dirname(selkies.__file__))
    from Xlib import X, Xatom, display as xdisplay

    d = xdisplay.Display()
    root = d.screen().root
    resources = d.intern_atom("RESOURCE_MANAGER")
    root.change_attributes(event_mask=X.PropertyChangeMask)

    def current_dpi():
        prop = root.get_full_property(resources, Xatom.STRING)
        text = prop.value.decode(errors="replace") if prop and isinstance(prop.value, bytes) else ""
        m = re.search(r"^Xft\.dpi:\s*([\d.]+)", text, re.M)
        return int(round(float(m.group(1)))) if m else BASE_DPI

    applied = current_dpi()
    if applied != BASE_DPI:  # the DPI changed while the session started
        write(applied)
        subprocess.run(["icewm", "--restart"], check=False)
    while True:
        e = d.next_event()
        if e.type != X.PropertyNotify or e.atom != resources:
            continue
        time.sleep(SETTLE_S)
        while d.pending_events():
            d.next_event()
        dpi = current_dpi()
        if dpi != applied:
            write(dpi)
            subprocess.run(["icewm", "--restart"], check=False)
            print(f"[desktop] IceWM rescaled for {dpi} DPI", flush=True)
            applied = dpi


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "setup":
        write(BASE_DPI)
    elif mode == "watch":
        watch()
    else:
        sys.exit(__doc__)
