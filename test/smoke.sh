#!/bin/bash
# End-to-end check that a built image actually works.
#
#   ./test/smoke.sh [image]
#
# Asserts the things that break silently: the desktop route serving is not the
# same as the desktop rendering, and a missing package usually shows up as a
# blank screen rather than a build failure.

set -uo pipefail

IMAGE="${1:-scidesktop}"
NAME="scidesktop-smoke-$$"
PORT="${SMOKE_PORT:-18999}"
TOKEN="smoke"
HERE="$(cd "$(dirname "$0")" && pwd)"
# Test container image for the Apptainer checks.
SMOKE_ALPINE="${SMOKE_ALPINE:-alpine:3.22}"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

# logs_have <container> <pattern>: whether the container's log has a line
# matching the extended regular expression. The log is saved before it is
# searched: under pipefail, `docker logs | grep -q` fails when grep finds its
# match and exits before docker has written the rest of a long log.
logs_have() {
    docker logs "$1" >"/tmp/$1.search.log" 2>&1
    grep -qE "$2" "/tmp/$1.search.log"
}

cleanup() {
    rm -f "/tmp/${NAME}.search.log" "/tmp/${NAME}-tile.search.log"
    docker logs "${NAME}" >/tmp/${NAME}.log 2>&1 || true
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
    for mode in disabled external internal; do
        docker rm -f "${NAME}-cvmfs-${mode}" >/dev/null 2>&1 || true
    done
    docker rm -f "${NAME}-singleuser" "${NAME}-hub" "${NAME}-userns" "${NAME}-tile" >/dev/null 2>&1 || true
    [ -z "${TILE_DIR:-}" ] || rm -rf "${TILE_DIR:?}"
}
trap cleanup EXIT

echo "smoke: ${IMAGE}"
docker run -d --name "${NAME}" -p "${PORT}:8888" --shm-size=2g \
    -e JUPYTER_TOKEN="${TOKEN}" "${IMAGE}" >/dev/null || { echo "  FAIL  container did not start"; exit 1; }

# 1. Jupyter answers
for _ in $(seq 1 120); do
    curl -fsS -o /dev/null "http://127.0.0.1:${PORT}/api" 2>/dev/null && break
    sleep 1
done
if curl -fsS -o /dev/null "http://127.0.0.1:${PORT}/api" 2>/dev/null; then
    pass "jupyter responds"
else
    fail "jupyter responds"; exit 1
fi

# Jupyter AI's chat is part of the page JupyterLab loads, in every image. A
# persona appears in it for each coding agent an image has; that, and the
# chat itself, need a browser.
page="$(curl -s -H "Authorization: token ${TOKEN}" "http://127.0.0.1:${PORT}/lab")"
if grep -q '"name": "jupyterlab-chat-extension"' <<<"${page}" && grep -q '"name": "@jupyter-ai/acp-client"' <<<"${page}" \
    && grep -q '"name": "@jupyter-ai/persona-manager"' <<<"${page}"; then
    pass "JupyterLab's page loads the Jupyter AI chat extensions"
else
    fail "JupyterLab's page loads the Jupyter AI chat extensions"
fi
docker exec "${NAME}" bash -lc 'jupyter server extension list' >"/tmp/${NAME}.extensions" 2>&1
if [ "$(grep -c -E '(jupyter_ai_acp_client|jupyter_ai_persona_manager|jupyter_ai_router|jupyterlab_chat|jupyter_live_content) .*OK' "/tmp/${NAME}.extensions")" = 5 ]; then
    pass "the notebook server loads the Jupyter AI extensions"
else
    fail "the notebook server loads the Jupyter AI extensions"
fi
rm -f "/tmp/${NAME}.extensions"
echo "        NOT TESTED: OPENING A JUPYTER AI CHAT AND ITS AGENT PERSONAS. THAT NEEDS A BROWSER."

# Server extensions reach what they wrap: jupyterlmod finds Lmod (through the
# start-up hook's environment), jupyterlab-git finds git.
body=$(curl -s -H "Authorization: token ${TOKEN}" "http://127.0.0.1:${PORT}/module/system" 2>/dev/null)
echo "${body}" | grep -qi lmod && pass "jupyterlmod finds Lmod" || fail "jupyterlmod finds Lmod (got: ${body:0:80})"
body=$(curl -s -H "Authorization: token ${TOKEN}" "http://127.0.0.1:${PORT}/git/settings" 2>/dev/null)
echo "${body}" | grep -q '"gitVersion": *"[0-9]' && pass "jupyterlab-git finds git" || fail "jupyterlab-git finds git (got: ${body:0:80})"
# The server settings are in effect: hidden files are served.
code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: token ${TOKEN}" \
    "http://127.0.0.1:${PORT}/api/contents/.bashrc?content=0" 2>/dev/null)
[ "${code}" = 200 ] && pass "hidden files served (server settings loaded)" \
    || fail "hidden files served (server settings loaded) (got HTTP ${code})"

# 2. The desktop route serves. This is what spawns selkies, so it is slow the
#    first time.
code=$(curl -s -o /tmp/${NAME}-desktop.html -w '%{http_code}' -m 180 \
    -H "Authorization: token ${TOKEN}" "http://127.0.0.1:${PORT}/desktop/")
[ "${code}" = "200" ] && pass "desktop route serves" || fail "desktop route serves (HTTP ${code})"

# 3. Only Jupyter listens on a routable port; selkies must stay on loopback.
external=$(docker exec "${NAME}" python3 -c "
ports=set()
for f in ('/proc/net/tcp','/proc/net/tcp6'):
    try:
        for line in open(f).readlines()[1:]:
            p=line.split()
            if p[3]=='0A':
                addr, port = p[1].split(':')
                if addr not in ('0100007F','00000000000000000000000001000000'):
                    ports.add(int(port,16))
    except Exception: pass
print(' '.join(str(p) for p in sorted(ports)))" 2>/dev/null)
[ "${external}" = "8888" ] && pass "only 8888 listens externally" \
    || fail "only 8888 listens externally (got: ${external:-none})"

# Selkies' interpreter, read from its launcher, so the checks below run
# wherever Selkies is installed; XPY opens the desktop with its python-xlib.
SELKIES_PY=$(docker exec "${NAME}" bash -c 'head -1 "$(readlink -f "$(command -v selkies)")" | sed "s/^#! *//"' 2>/dev/null)
XPY="import sys, os, selkies
sys.path.insert(0, os.path.dirname(selkies.__file__))
from Xlib import X, display as xd
d = xd.Display(':20'); r = d.screen().root"
NB_USER=$(docker exec "${NAME}" printenv NB_USER 2>/dev/null || echo jovyan)
# PipeWire has an output for Selkies to capture.
audio_ok() {
    docker exec -u "${NB_USER}" "$1" bash -c \
        'XDG_RUNTIME_DIR=/tmp/runtime-$(id -u) wpctl inspect @DEFAULT_AUDIO_SINK@' 2>/dev/null \
        | grep -q 'node.name'
}

# 4. The session is actually up
# The session and its window manager.
for proc in Xvfb icewm-session icewm xsettingsd pipewire wireplumber pipewire-pulse; do
    docker exec "${NAME}" pgrep -x "${proc}" >/dev/null 2>&1 \
        && pass "${proc} running" || fail "${proc} running"
done
docker exec "${NAME}" bash -c 'test -S "${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}/pulse/native"' 2>/dev/null \
    && pass "pulseaudio socket up" || fail "pulseaudio socket up"
audio_ok "${NAME}" && pass "audio output present" || fail "audio output present"
docker exec "${NAME}" xrdb -query 2>/dev/null | grep -q '^Xcursor.size:[[:space:]]*24$' \
    && pass "pointer size set (not scaled to the virtual screen)" \
    || fail "pointer size set (not scaled to the virtual screen)"
# A 2x browser: Selkies sets Xft.dpi 192, and IceWM's taskbar grows with it
# (read from the work area IceWM leaves beside it), then shrinks back.
docker exec "${NAME}" "${SELKIES_PY:-python3}" -c "${XPY}
import subprocess, time
a = d.intern_atom('_NET_WORKAREA')
def taskbar(test):
    for _ in range(100):
        p = r.get_full_property(a, X.AnyPropertyType)
        h = r.get_geometry().height - p.value[3] if p else None
        if h is not None and test(h):
            break
        time.sleep(0.1)
    return h
def dpi(v): subprocess.run(['xrdb', '-merge'], input=f'Xft.dpi: {v}\\n', text=True, check=True)
small = taskbar(lambda h: h > 0)
dpi(192); big = taskbar(lambda h: h > small)
dpi(96); back = taskbar(lambda h: h == small)
print(f'taskbar {small} px at 96 DPI, {big} px at 192, {back} px back at 96')
sys.exit(0 if small and big > small and back == small else 1)" 2>&1 | sed 's/^/        /'
[ "${PIPESTATUS[0]}" = "0" ] && pass "IceWM's taskbar follows the desktop DPI" \
    || fail "IceWM's taskbar follows the desktop DPI"
# Every IceWM toolbar launcher (including Terminal and Files) has an existing
# icon file and renders pixels that visibly differ from the empty taskbar
# background rather than a blank slot.
docker exec "${NAME}" "${SELKIES_PY:-python3}" -c "${XPY}
import re, sys, time
from collections import Counter
from Xlib import error as xerror
tb_icons = []
for line in open('/etc/X11/icewm/toolbar'):
    m = re.match(r'^prog\s+\"([^\"]+)\"\s+(\S+)\s+(.+)$', line.strip())
    if m:
        tb_icons.append((m.group(1), m.group(2), m.group(3)))
missing_files = [f'{n}:{p}' for n, p, _ in tb_icons if not (p.startswith('/') and os.path.isfile(p) and os.path.getsize(p) > 0)]
if missing_files:
    print('missing toolbar icon files:', ', '.join(missing_files))
    sys.exit(1)
expected = [n for n, _, _ in tb_icons]
depth = r.get_geometry().depth
bpp = next((fmt.bits_per_pixel for fmt in d.display.info.pixmap_formats if fmt.depth == depth), 32)
stride = max(1, bpp // 8)
def pixels_of(win):
    g = win.get_geometry()
    if g.width <= 0 or g.height <= 0:
        return []
    pt = r.translate_coords(win, 0, 0)
    raw = r.get_image(pt.x, pt.y, g.width, g.height, X.ZPixmap, 0xffffffff).data
    if isinstance(raw, str):
        raw = raw.encode('latin-1')
    return [raw[i:i+min(3, stride)] for i in range(0, len(raw), stride)]
def find_win(w, name):
    if w.get_wm_name() == name:
        return w
    for c in w.query_tree().children:
        res = find_win(c, name)
        if res:
            return res
    return None
diff_counts = {}
for _ in range(50):
    try:
        tb = find_win(r, 'IceToolbar')
        pane = find_win(r, 'TaskPane')
        if tb is not None and pane is not None:
            pane_px = pixels_of(pane)
            if not pane_px:
                time.sleep(0.1)
                continue
            bg = Counter(pane_px).most_common(1)[0][0]
            cur = {}
            for btn in tb.query_tree().children:
                name = btn.get_wm_name()
                px = pixels_of(btn)
                if not px:
                    continue
                cur[name] = sum(1 for p in px if p != bg)
            diff_counts = cur
            if expected and all(diff_counts.get(n, 0) >= 64 for n in expected):
                break
    except xerror.XError:
        pass
    time.sleep(0.1)
blank = [n for n in expected if diff_counts.get(n, 0) < 64]
print('toolbar buttons:', ', '.join(f'{n}={diff_counts.get(n, 0)} icon px' for n in expected))
sys.exit(0 if expected and 'Terminal' in expected and not blank else 1)" 2>&1 | sed 's/^/        /'
[ "${PIPESTATUS[0]}" = "0" ] && pass "IceWM toolbar icons (including Terminal) render visibly" \
    || fail "IceWM toolbar icons (including Terminal) render visibly"

# Clicking the Terminal taskbar button opens xfce4-terminal with an interactive
# bash shell where `ml` can load a module without CVMFS.
docker exec -u "${NB_USER}" "${NAME}" bash -c '
    set -euo pipefail
    mod_dir=$(mktemp -d /tmp/smoke-mod.XXXXXX)
    out_file="${mod_dir}/out"
    trap "rm -rf \"\${mod_dir}\"" EXIT
    mkdir -p "${mod_dir}/smokemod"
    printf "setenv(\"SCIDESKTOP_SMOKE_ML\", \"ml_ok\")\n" > "${mod_dir}/smokemod/1.0.lua"
    "'"${SELKIES_PY:-python3}"'" - "${mod_dir}" "${out_file}" <<'\''PY'\''
import os, sys, time, selkies
sys.path.insert(0, os.path.dirname(selkies.__file__))
from Xlib import X, XK, display as xd, error as xerror
from Xlib.ext import xtest

mod_dir, out_file = sys.argv[1], sys.argv[2]
d = xd.Display(":20")
r = d.screen().root
cl_atom = d.intern_atom("_NET_CLIENT_LIST")
active_atom = d.intern_atom("_NET_ACTIVE_WINDOW")

def find_win(w, name):
    if w.get_wm_name() == name:
        return w
    for c in w.query_tree().children:
        res = find_win(c, name)
        if res:
            return res
    return None

def clients():
    p = r.get_full_property(cl_atom, X.AnyPropertyType)
    return list(p.value) if p else []

before = set(clients())
btn = find_win(r, "Terminal")
assert btn is not None, "Terminal toolbar button not found"
g = btn.get_geometry()
pt = r.translate_coords(btn, g.width // 2, g.height // 2)
xtest.fake_input(d, X.MotionNotify, x=pt.x, y=pt.y)
xtest.fake_input(d, X.ButtonPress, 1)
xtest.fake_input(d, X.ButtonRelease, 1)
d.sync()

term_wid = None
for _ in range(100):
    for wid in clients():
        if wid in before:
            continue
        try:
            cls = d.create_resource_object("window", wid).get_wm_class() or ()
        except xerror.XError:
            continue
        if any("xfce4-terminal" in c.lower() for c in cls):
            term_wid = wid
            break
    if term_wid is not None:
        break
    time.sleep(0.1)
assert term_wid is not None, "xfce4-terminal window did not open after clicking Terminal"

# Wait briefly for bash inside xfce4-terminal to initialize and focus the window.
term_win = d.create_resource_object("window", term_wid)
for _ in range(50):
    p = r.get_full_property(active_atom, X.AnyPropertyType)
    if p and p.value and p.value[0] == term_wid:
        break
    time.sleep(0.1)
time.sleep(1.5)

shift_kc = d.keysym_to_keycode(XK.XK_Shift_L)
SPECIAL = {
    "\n": XK.XK_Return, " ": XK.XK_space, "/": XK.XK_slash, ".": XK.XK_period,
    "-": XK.XK_minus, "_": XK.XK_underscore, ">": XK.XK_greater, ";": XK.XK_semicolon,
    "$": XK.XK_dollar, "=": XK.XK_equal, "\"": XK.XK_quotedbl,
}
def send_text(text):
    for ch in text:
        ks = SPECIAL.get(ch, XK.string_to_keysym(ch))
        codes = list(d.keysym_to_keycodes(ks))
        assert codes, f"no keycode for {ch!r} (keysym {ks})"
        kc, idx = codes[0]
        need_shift = (idx % 2 == 1)
        if need_shift:
            xtest.fake_input(d, X.KeyPress, shift_kc)
        xtest.fake_input(d, X.KeyPress, kc)
        xtest.fake_input(d, X.KeyRelease, kc)
        if need_shift:
            xtest.fake_input(d, X.KeyRelease, shift_kc)
    d.sync()

cmd = f"ml use {mod_dir}; ml load smokemod; printenv SCIDESKTOP_SMOKE_ML > {out_file}; exit\n"
send_text(cmd)

for _ in range(100):
    if os.path.exists(out_file) and os.path.getsize(out_file) > 0:
        break
    time.sleep(0.1)
assert os.path.exists(out_file), "command in clicked Terminal did not produce output"
val = open(out_file).read().strip()
assert val == "ml_ok", f"expected ml_ok, got {val!r}"
for _ in range(50):
    if term_wid not in clients():
        break
    time.sleep(0.1)
PY
' 2>&1 | sed 's/^/        /'
[ "${PIPESTATUS[0]}" = "0" ] && pass "clicking Terminal toolbar button opens bash with working ml load" \
    || fail "clicking Terminal toolbar button opens bash with working ml load"

# 5. Real pixels. A desktop that fails to draw still serves HTTP, so read the
#    framebuffer rather than trusting the status code.
framebuffer_ok() {
    docker exec "$1" "${SELKIES_PY:-python3}" -c "${XPY}
from collections import Counter
g = r.get_geometry()
data = r.get_image(0, 0, min(g.width, 400), min(g.height, 300), 2, 0xffffffff).data
if isinstance(data, str): data = data.encode('latin-1')
px = [tuple(data[i:i+3]) for i in range(0, 4*400, 4)]
top, count = Counter(px).most_common(1)[0]
print(f'geometry {g.width}x{g.height} dominant {top} n={count}')
sys.exit(0 if g.width > 0 else 1)" 2>/dev/null | sed 's/^/        /'
    return "${PIPESTATUS[0]}"
}
framebuffer_ok "${NAME}" && pass "framebuffer readable" || fail "framebuffer readable"

# 5b. The encoders import. The framebuffer check above passes even when
#     selkies cannot encode it, so the desktop serves, renders, and streams
#     nothing. Encoder errors only appear once a client asks for a stream, so
#     the log check below is a backstop rather than proof.
docker exec "${NAME}" "${SELKIES_PY:-python3}" -c 'import pixelflux, pcmflux' >/dev/null 2>&1 \
    && pass "encoders import" || fail "encoders import"
if logs_have "${NAME}" "failed to import|video pipeline did not start"; then
    fail "no encoder errors logged"
    docker logs "${NAME}" 2>&1 | grep -E "failed to import|did not start" | tail -2 | sed 's/^/        /'
else
    pass "no encoder errors logged"
fi

# 6. module is on the path for interactive shells
docker exec "${NAME}" bash -lc 'type -t module' 2>/dev/null | grep -q function \
    && pass "module available" || fail "module available"
docker exec "${NAME}" bash -lc 'case ":${XDG_DATA_DIRS}:" in *:/opt/sciget:*) exit 0;; *) exit 1;; esac' 2>/dev/null \
    && pass "sciget applications on login-shell data path" \
    || fail "sciget applications on login-shell data path"
# Interactive shells, login (JupyterLab terminal) and not (desktop terminal),
# start without warnings and have module, ml and mamba.
for mode in -ic -lic; do
    out=$(docker exec -u "$(docker exec "${NAME}" printenv NB_USER 2>/dev/null || echo jovyan)" -w /tmp "${NAME}" \
        bash "${mode}" 'type -t module >/dev/null && type -t ml >/dev/null && type -t mamba >/dev/null && echo SHELL_OK' 2>&1 \
        | sed 's/\x1b\[[0-9;]*m//g' \
        | grep -v -e 'cannot set terminal process group' -e 'no job control' \
        | grep -vxF -f <(docker exec "${NAME}" cat /tmp/.scidesktop-containers-unavailable 2>/dev/null))
    if [ "$(printf '%s' "${out}")" = SHELL_OK ]; then
        pass "bash ${mode}: clean, module, ml and mamba"
    else
        fail "bash ${mode}: clean, module, ml and mamba"; printf '%s\n' "${out}" | head -5 | sed 's/^/        /'
    fi
done
# sciget arrives configured from its system layer, with nothing copied into
# the home. Which catalog an image has is its catalog component's to check
# (test/sciget-catalog-check.sh); the base has none.
docker exec -u "${NB_USER}" "${NAME}" bash -c '
    sciget catalog list >/dev/null && [ ! -e ~/.config/sciget/catalogs.json ] \
        && sciget config get display_start_command | grep -q /opt/scidesktop/start_desktop.sh' 2>/dev/null \
    && pass "sciget settings from the system layer" \
    || fail "sciget settings from the system layer"

# Files that component tests cannot check on the OS layer, which has no
# Python: sciget's system settings are valid JSON (sciget ignores a malformed
# file) and the startup scripts parse.
docker exec "${NAME}" python3 -c '
import ast, json
json.load(open("/etc/sciget/config.json"))
for f in ("/usr/local/bin/start-notebook.py", "/usr/local/bin/start-singleuser.py"):
    ast.parse(open(f).read())
' >/dev/null 2>&1 && pass "sciget settings valid JSON, startup scripts parse" \
    || fail "sciget settings valid JSON, startup scripts parse"

# Every component's manifest entry is present and readable by the user.
docker exec "${NAME}" python3 -c '
import glob, json, sys
names = {p.split("/")[-1][:-5] for p in glob.glob("/opt/scidesktop/manifest.d/*.json")}
[json.load(open(p)) for p in glob.glob("/opt/scidesktop/manifest.d/*.json")]
need = {"os-ubuntu", "startup", "jupyter-env", "selkies", "apptainer", "lmod", "sciget", "slurm"}
sys.exit(0 if need <= names else f"missing: {need - names}")' >/dev/null 2>&1 \
    && pass "version manifest complete" || fail "version manifest complete"
# Shared folders stay traversable for the user (a linked layer once made
# /usr/local/share unreadable).
docker exec "${NAME}" bash -c 'for d in /usr/local/share /usr/local/bin /usr/local/etc /etc/profile.d /opt; do [ -x "$d" ] || exit 1; done' 2>/dev/null \
    && pass "shared folders traversable" || fail "shared folders traversable"

# Image hygiene & security baseline (shared with test/flavour-smoke.sh).
"${HERE}/hygiene-check.sh" "${NAME}" "${NB_USER}" || FAILED=$((FAILED + 1))

# 7. Apptainer, and the pieces unprivileged builds fall back to. Whether a
#    build actually succeeds depends on the runtime granting user namespaces,
#    so that is checked separately under SMOKE_BUILD=1.
docker exec "${NAME}" bash -lc 'apptainer --version' >/dev/null 2>&1 \
    && pass "apptainer runs" || fail "apptainer runs"
for f in /opt/apptainer/libexec/apptainer/bin/proot /opt/apptainer/libexec/apptainer/bin/mksquashfs; do
    docker exec "${NAME}" test -f "${f}" 2>/dev/null \
        && pass "$(basename "${f}") vendored" || fail "$(basename "${f}") vendored"
done
docker exec "${NAME}" bash -c 'command -v fakeroot' >/dev/null 2>&1 \
    && pass "fakeroot present" || fail "fakeroot present"
# Apptainer ships with setuid off and uses user namespaces, as on the
# Kubernetes deployment.
actual_setuid=$(docker exec "${NAME}" awk -F ' = ' '/^allow setuid = / { print $2; exit }' \
    /opt/apptainer/etc/apptainer/apptainer.conf 2>/dev/null)
[ "${actual_setuid}" = no ] && pass "apptainer setuid off by default" \
    || fail "apptainer setuid off by default (got ${actual_setuid:-missing})"
# The server, and everything it starts, names the home for Apptainer.
docker exec -u "${NB_USER}" "${NAME}" sh -c \
    'tr "\0" "\n" </proc/$(pgrep -o -f "jupyter-lab|jupyter lab")/environ' 2>/dev/null \
    | grep -qx "APPTAINER_HOME=/home/${NB_USER}" \
    && pass "APPTAINER_HOME set for the Jupyter server" \
    || fail "APPTAINER_HOME set for the Jupyter server"
# Users are told when containers cannot run. Where the notebook user cannot
# even create a user namespace, the warning must be there; the check against
# Apptainer itself is with the user-namespace check below.
if ! docker exec -u "${nb_user:-jovyan}" "${NAME}" unshare -U true >/dev/null 2>&1; then
    docker exec "${NAME}" test -e /tmp/.scidesktop-containers-unavailable \
        && pass "containers-unavailable warning where user namespaces are denied" \
        || fail "containers-unavailable warning where user namespaces are denied"
fi
docker exec "${NAME}" bash -lc 'cvmfs2 --version' >/dev/null 2>&1 \
    && pass "cvmfs present" || fail "cvmfs present"

# 7b. Every CVMFS mode lets start.sh reach its command and reports the
#     decision it made. Disabled mode is deliberately silent.
for mode in disabled external internal; do
    mode_name="${NAME}-cvmfs-${mode}"
    mode_log="/tmp/${mode_name}.log"
    if docker run --name "${mode_name}" -e SCIDESKTOP_CVMFS_MODE="${mode}" \
        "${IMAGE}" bash -lc 'echo scidesktop-smoke-command-ran' >"${mode_log}" 2>&1 \
        && grep -q '^scidesktop-smoke-command-ran$' "${mode_log}"; then
        pass "cvmfs ${mode} mode survives startup"
    else
        fail "cvmfs ${mode} mode survives startup"
    fi

    case "${mode}" in
    disabled)
        if grep -q '^\[cvmfs\]' "${mode_log}"; then
            fail "cvmfs disabled mode is silent"
        else
            pass "cvmfs disabled mode is silent"
        fi
        ;;
    external)
        grep -qE '^\[cvmfs\] (using mounted /cvmfs:|/cvmfs is empty;)' "${mode_log}" \
            && pass "cvmfs external mode logs its decision" \
            || fail "cvmfs external mode logs its decision"
        ;;
    internal)
        grep -qE '^\[cvmfs\] (internal mode needs root|no /dev/fuse|internal mode needs SCIDESKTOP_CVMFS_REPOSITORIES); skipping$' "${mode_log}" \
            && pass "cvmfs internal mode logs its prerequisite" \
            || fail "cvmfs internal mode logs its prerequisite"
        ;;
    esac
    docker rm "${mode_name}" >/dev/null 2>&1 || true
done

# 8. Nothing from the neurodesk lineage came along. An image that copies a
#    neurodesk-* component holds that component's /opt/neurodesk-* folder,
#    which rule I1 accounts for; nothing else of the lineage belongs in any
#    image.
nd_stray=""
if ! nd_stray=$(docker exec "${NAME}" bash -c '
    for path in /opt/neurodesk* /neurocommand /cvmfs/neurodesk*; do
        [ -e "${path}" ] || continue
        [ -e "/opt/scidesktop/manifest.d/${path#/opt/}.json" ] || echo "${path}"
    done
    if [ -e /opt/nf-neuro ] && [ ! -e /opt/scidesktop/manifest.d/neurodesk-compat.json ]; then
        echo /opt/nf-neuro
    fi
    if [ -e /opt/neuroimaging-env ] && [ ! -e /opt/scidesktop/manifest.d/neuroimaging-env.json ]; then
        echo /opt/neuroimaging-env
    fi' 2>/dev/null); then
    fail "no neurodesk payload outside a neurodesk-* component (exec failed)"
elif [ -n "${nd_stray}" ]; then
    fail "no neurodesk payload outside a neurodesk-* component (${nd_stray})"
else
    pass "no neurodesk payload outside a neurodesk-* component"
fi

# 8b. The desktop comes back after a container restart, which kills the
#     session without cleanup and leaves its X socket behind.
docker restart "${NAME}" >/dev/null
for _ in $(seq 1 120); do
    curl -fsS -o /dev/null "http://127.0.0.1:${PORT}/api" 2>/dev/null && break
    sleep 0.5
done
code=$(curl -s -o /dev/null -w '%{http_code}' -m 180 \
    -H "Authorization: token ${TOKEN}" "http://127.0.0.1:${PORT}/desktop/")
session_back() {
    local proc up
    for proc in Xvfb icewm pipewire wireplumber pipewire-pulse; do
        up=
        for _ in $(seq 1 100); do
            docker exec "${NAME}" pgrep -x "${proc}" >/dev/null 2>&1 && up=1 && break
            sleep 0.1
        done
        [ -n "${up}" ] || { echo "no (${proc} not running)"; return; }
    done
    for _ in $(seq 1 50); do audio_ok "${NAME}" && break; sleep 0.1; done
    audio_ok "${NAME}" || { echo "no (no audio output)"; return; }
    framebuffer_ok "${NAME}" >/dev/null || { echo "no (framebuffer unreadable)"; return; }
    echo yes
}
restarted=$(session_back)
[ "${code}" = 200 ] && [ "${restarted}" = yes ] && pass "desktop returns after a container restart" \
    || fail "desktop returns after a container restart (HTTP ${code}, ${restarted})"

# 8c. The desktop comes back when its X server dies in a running container
#     (an out-of-memory kill, say): the session ends and Selkies' launcher
#     starts a new one.
docker exec "${NAME}" pkill -x Xvfb
for _ in $(seq 1 100); do
    docker exec "${NAME}" pgrep -x pipewire >/dev/null 2>&1 || break
    sleep 0.1
done
restarted=$(session_back)
# Selkies restarts with the session: the route answers once it is back.
for _ in $(seq 1 30); do
    code=$(curl -s -o /dev/null -w '%{http_code}' -m 60 \
        -H "Authorization: token ${TOKEN}" "http://127.0.0.1:${PORT}/desktop/")
    [ "${code}" = 200 ] && break
    sleep 1
done
[ "${code}" = 200 ] && [ "${restarted}" = yes ] && pass "desktop returns after its X server dies" \
    || fail "desktop returns after its X server dies (HTTP ${code}, ${restarted})"

# 9. JupyterHub spawn. KubeSpawner runs start-singleuser.py with the Hub's
#    environment; the server checks the Hub API before serving, so a stand-in
#    answers that check from a container sharing its network namespace.
SU_PORT="${SMOKE_SINGLEUSER_PORT:-18998}"
FAKE_HUB='import http.server, json
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.end_headers(); self.wfile.write(json.dumps({"version": "0"}).encode())
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", 8081), H).serve_forever()'
docker run -d --name "${NAME}-hub" -p "${SU_PORT}:8888" --entrypoint /opt/conda/bin/python \
    "${IMAGE}" -c "${FAKE_HUB}" >/dev/null
docker run -d --name "${NAME}-singleuser" --network "container:${NAME}-hub" \
    -e JUPYTERHUB_API_TOKEN=smoke -e JUPYTERHUB_API_URL=http://127.0.0.1:8081/hub/api \
    -e JUPYTERHUB_USER=smoke -e JUPYTERHUB_CLIENT_ID=jupyterhub-user-smoke \
    -e JUPYTERHUB_SERVICE_PREFIX=/user/smoke/ -e JUPYTERHUB_BASE_URL=/ \
    -e JUPYTERHUB_SERVICE_URL=http://0.0.0.0:8888/user/smoke/ \
    -e JUPYTERHUB_OAUTH_CALLBACK_URL=/user/smoke/oauth_callback \
    "${IMAGE}" start-singleuser.py >/dev/null
su_code=000
for _ in $(seq 1 120); do
    su_code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${SU_PORT}/user/smoke/api" 2>/dev/null)
    [ "${su_code}" = 200 ] && break
    sleep 0.5
done
[ "${su_code}" = 200 ] && pass "singleuser server serves under its Hub prefix" \
    || fail "singleuser server serves under its Hub prefix (HTTP ${su_code})"
lab_code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${SU_PORT}/user/smoke/lab" 2>/dev/null)
[ "${lab_code}" = 302 ] && pass "singleuser sends unauthenticated users to the Hub" \
    || fail "singleuser sends unauthenticated users to the Hub (HTTP ${lab_code})"
docker rm -f "${NAME}-singleuser" "${NAME}-hub" >/dev/null 2>&1 || true

# App tiles: a desktop entry in sciget's applications folder becomes a
# JupyterLab launcher tile, and the tile starts the application maximised
# on the desktop (desktop_app.py), starting the desktop first.
TILE_PORT="${SMOKE_TILE_PORT:-18997}"
TILE_DIR=$(mktemp -d)
printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Smoke terminal' \
    'Exec=xfce4-terminal --title=smoke-tile' > "${TILE_DIR}/smoke-terminal.desktop"
chmod -R a+rX "${TILE_DIR}"
docker run -d --name "${NAME}-tile" -p "${TILE_PORT}:8888" --shm-size=1g \
    -e JUPYTER_TOKEN="${TOKEN}" -v "${TILE_DIR}:/opt/sciget/applications:ro" "${IMAGE}" >/dev/null
for _ in $(seq 1 120); do
    curl -fsS -o /dev/null "http://127.0.0.1:${TILE_PORT}/api" 2>/dev/null && break
    sleep 0.5
done
curl -s "http://127.0.0.1:${TILE_PORT}/server-proxy/servers-info?token=${TOKEN}" 2>/dev/null \
    | grep -q '"app-smoke-terminal"' \
    && pass "app tile registered from sciget's applications folder" \
    || fail "app tile registered from sciget's applications folder"
tile_code=$(curl -s -o /dev/null -w '%{http_code}' -m 120 \
    "http://127.0.0.1:${TILE_PORT}/app-smoke-terminal/launch?token=${TOKEN}" 2>/dev/null)
for _ in $(seq 1 60); do
    logs_have "${NAME}-tile" "window 0x[0-9a-f]* maximised" && break
    sleep 0.5
done
if [ "${tile_code}" = 200 ] && logs_have "${NAME}-tile" "window 0x[0-9a-f]* maximised"; then
    pass "app tile starts its application maximised"
else
    fail "app tile starts its application maximised (HTTP ${tile_code})"
    docker logs "${NAME}-tile" 2>&1 | grep -E "desktop-app|\[desktop\]" | tail -5 | sed 's/^/        /'
fi
# After a container restart the tile, not the desktop route, is the first to
# find the stale session.
docker restart "${NAME}-tile" >/dev/null
for _ in $(seq 1 120); do
    curl -fsS -o /dev/null "http://127.0.0.1:${TILE_PORT}/api" 2>/dev/null && break
    sleep 0.5
done
tile_code=$(curl -s -o /dev/null -w '%{http_code}' -m 120 \
    "http://127.0.0.1:${TILE_PORT}/app-smoke-terminal/launch?token=${TOKEN}" 2>/dev/null)
for _ in $(seq 1 60); do
    [ "$(docker logs "${NAME}-tile" 2>&1 | grep -c "window 0x[0-9a-f]* maximised")" -ge 2 ] && break
    sleep 0.5
done
if [ "${tile_code}" = 200 ] && [ "$(docker logs "${NAME}-tile" 2>&1 | grep -c "window 0x[0-9a-f]* maximised")" -ge 2 ]; then
    pass "app tile starts its application after a container restart"
else
    fail "app tile starts its application after a container restart (HTTP ${tile_code})"
    docker logs "${NAME}-tile" 2>&1 | grep -E "desktop-app|\[desktop\]" | tail -5 | sed 's/^/        /'
fi
docker rm -f "${NAME}-tile" >/dev/null 2>&1 || true
rm -rf "${TILE_DIR:?}"; TILE_DIR=""

# Apptainer runs a container as the user, the way the Kubernetes deployment
# runs pods: not privileged, no /dev/fuse, AppArmor and seccomp relaxed (the
# cluster's `notebook` AppArmor profile allows user namespaces and mounts).
# Pulls alpine from Docker Hub; SMOKE_APPTAINER=0 skips it.
if [ "${SMOKE_APPTAINER:-1}" = "1" ]; then
    docker rm -f "${NAME}-userns" >/dev/null 2>&1 || true
    docker run -d --name "${NAME}-userns" --security-opt apparmor=unconfined \
        --security-opt seccomp=unconfined -e JUPYTER_TOKEN=x "${IMAGE}" >/dev/null
    for _ in $(seq 1 60); do docker exec "${NAME}-userns" curl -fsS -o /dev/null localhost:8888/api 2>/dev/null && break; sleep 0.5; done
    # Whether Apptainer runs a container as the user in container $1, in a
    # new sandbox each time; the log is left at /tmp/userns.log there.
    apptainer_runs() {
        docker exec -e SMOKE_ALPINE="${SMOKE_ALPINE}" -w /tmp "$1" bash -lc '
            sb=$(mktemp -d -u /tmp/sb.XXXXXX)
            apptainer build --sandbox "${sb}" docker://${SMOKE_ALPINE} >/tmp/userns.log 2>&1 \
              && apptainer exec "${sb}" cat /etc/alpine-release 2>>/tmp/userns.log' >/dev/null 2>&1
    }
    if apptainer_runs "${NAME}-userns"; then
        pass "apptainer runs a container as the user (user namespaces)"
    else
        fail "apptainer runs a container as the user (user namespaces)"
        docker exec "${NAME}-userns" tail -5 /tmp/userns.log 2>/dev/null | sed 's/^/        /'
        echo "        host: kernel $(uname -r), $(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null | sed 's/^/apparmor_restrict_unprivileged_userns=/')"
    fi
    # The warning is shown exactly where Apptainer cannot run: here and under
    # Docker's default security options.
    for c in "${NAME}-userns:relaxed" "${NAME}:default"; do
        apptainer_runs "${c%:*}" && runs=yes || runs=no
        docker exec "${c%:*}" test -e /tmp/.scidesktop-containers-unavailable && warned=yes || warned=no
        [ "${warned}" != "${runs}" ] \
            && pass "containers-unavailable warning matches Apptainer (${c##*:} security, runs: ${runs})" \
            || fail "containers-unavailable warning matches Apptainer (${c##*:} security, runs: ${runs}, warned: ${warned})"
    done
    docker rm -f "${NAME}-userns" >/dev/null 2>&1 || true
fi

# Optional: build a container for real. Needs a privileged container, because
# Apptainer requires user namespaces, which Docker denies to unprivileged
# containers on most hosts. Runs as root in a privileged container, which is
# how neurodesktop's own launcher runs. Off by default.
if [ "${SMOKE_BUILD:-0}" = "1" ]; then
    echo "  .. building a container (privileged)"
    docker rm -f "${NAME}-build" >/dev/null 2>&1 || true
    docker run -d --name "${NAME}-build" --privileged "${IMAGE}" sleep 600 >/dev/null
    if docker exec -e SMOKE_ALPINE="${SMOKE_ALPINE}" -u root "${NAME}-build" bash -lc '
        printf "Bootstrap: docker\nFrom: ${SMOKE_ALPINE}\n%%post\n    echo ok > /marker\n" > /tmp/t.def
        apptainer build --force /tmp/t.sif /tmp/t.def >/tmp/build.log 2>&1 \
          && apptainer exec /tmp/t.sif cat /marker | grep -q ok' 2>/dev/null; then
        pass "apptainer builds and runs a container"
    else
        fail "apptainer builds and runs a container"
        docker exec -u root "${NAME}-build" tail -5 /tmp/build.log 2>/dev/null | sed 's/^/        /'
    fi
    docker rm -f "${NAME}-build" >/dev/null 2>&1 || true
fi

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "smoke: all checks passed"
else
    echo "smoke: ${FAILED} check(s) failed; container log at /tmp/${NAME}.log"
fi
exit "${FAILED}"
