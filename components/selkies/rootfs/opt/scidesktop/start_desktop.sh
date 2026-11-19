#!/bin/bash
# Bring up the desktop session: Xvfb, IceWM, PipeWire. IceWM gives a taskbar
# and maximised applications (settings in /etc/X11/icewm).
# Called by start_selkies.sh on first use, not at container boot.

export DISPLAY="${DISPLAY:-:20}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
mkdir -p "${XDG_RUNTIME_DIR}"
# IceWM runs commands from its configuration there: refuse a folder someone
# else made in a shared /tmp.
if [ ! -O "${XDG_RUNTIME_DIR}" ] || ! chmod 700 "${XDG_RUNTIME_DIR}"; then
    echo "[desktop] ERROR: ${XDG_RUNTIME_DIR} is not ours" >&2
    exit 1
fi

# One session per container. Selkies and the app tiles both start it on
# demand; a second caller exits while this script holds the lock, after
# waiting briefly for an ending session's script to let go. The session's
# processes start without it (9>&-), so the lock goes with the script, which
# lives as long as the X server.
exec 9>"${XDG_RUNTIME_DIR}/desktop.lock"
flock -w 5 9 || { echo "[desktop] session already starting"; exit 0; }

# The session ends with its X server: stop what is left of it (audio, the DPI
# watcher) so the next caller starts a whole new one. Callers start this
# script in its own process group (setsid).
end_session() { trap - EXIT; kill -- -$$ 2>/dev/null; }
trap end_session EXIT
trap 'exit 1' TERM INT HUP

# Strip any ".screen" suffix: DISPLAY=:20.0 would look for X20.0.
DISPLAY_NUM="${DISPLAY#*:}"
X_SOCKET="/tmp/.X11-unix/X${DISPLAY_NUM%%.*}"
x_alive() { xrdb -query >/dev/null 2>&1; }

# A container restart kills the session without cleanup. Its X socket and lock
# would stop Xvfb from starting and look like a running server; its audio
# sockets would pass the PipeWire wait below before PipeWire listens.
if ! x_alive; then
    rm -rf "${X_SOCKET}" "/tmp/.X${DISPLAY_NUM%%.*}-lock" "${XDG_RUNTIME_DIR}/desktop.env" \
        "${XDG_RUNTIME_DIR}"/pipewire-0* "${XDG_RUNTIME_DIR}/pulse"
fi

# Oversized screen leaves room for client-driven resize. -ac lets any local
# client connect, so only the socket file listens: the abstract socket is
# reachable from every container in the pod's network namespace.
xvfb_pid=
if [ ! -S "${X_SOCKET}" ]; then
    /usr/bin/Xvfb "${DISPLAY}" -screen 0 "${SCIDESKTOP_XVFB_SCREEN:-8192x4096x24}" \
        +extension COMPOSITE +extension DAMAGE +extension GLX \
        +extension RANDR +extension RENDER +extension MIT-SHM \
        +extension XFIXES +extension XTEST \
        +iglx +render -nolisten tcp -nolisten local -ac -noreset -shmem -s 0 -dpms \
        >/tmp/Xvfb.log 2>&1 9>&- &
    xvfb_pid=$!

    # Up to 30 s, checked often: the desktop route waits on this.
    for _ in $(seq 1 600); do
        [ -S "${X_SOCKET}" ] && x_alive && break
        sleep 0.05
    done
fi

if ! x_alive; then
    echo "[desktop] ERROR: X server did not start; see /tmp/Xvfb.log" >&2
    exit 1
fi
echo "[desktop] Xvfb ready on ${DISPLAY}"

# Without a size, Xcursor scales the pointer to the screen height (1/48), so
# the oversized virtual screen gets a 96 px pointer. As a server resource it
# applies to every client, including applications in containers; Selkies
# scales it with the DPI (SELKIES_CURSOR_SIZE in start_selkies.sh).
# Xft.dpi starts at 96 too: Selkies reads the server's resources before the
# DPI an earlier session saved in ~/.Xresources, then sets the browser's.
# start_selkies.sh waits for these before starting Selkies.
printf '%s\n' 'Xcursor.size: 24' 'Xft.dpi: 96' | xrdb -merge

# One D-Bus session for the desktop and the audio stack. Without an address in
# its environment PipeWire auto-launches its own bus through the X server,
# which can stall it for seconds and leave WirePlumber unable to connect.
eval "$(/usr/bin/dbus-launch --sh-syntax --exit-with-x11 9>&-)"
export DBUS_SESSION_BUS_ADDRESS
# GTK applications take their DPI from XSETTINGS. Selkies rewrites
# ~/.xsettingsd with the browser's DPI and signals xsettingsd; start at 96 DPI
# like the X resources, so a DPI left by an earlier session does not apply.
xsettings="${HOME}/.xsettingsd"
{ grep -v '^Xft/DPI[[:space:]]' "${xsettings}" 2>/dev/null; printf 'Xft/DPI %d\n' $((96 * 1024)); } \
    >"${xsettings}.tmp" && mv -f "${xsettings}.tmp" "${xsettings}"
xsettingsd >/tmp/xsettingsd.log 2>&1 9>&- &

# IceWM's pixel sizes follow the DPI Selkies sets from the browser: its
# configuration comes from a runtime folder that desktop_scale.py rewrites.
export ICEWM_PRIVCFG="${XDG_RUNTIME_DIR}/icewm"
/opt/selkies/bin/python /opt/scidesktop/desktop_scale.py setup
# Without icewmbg: painting the oversized screen's background delays Selkies'
# start by about 0.5 s.
/usr/bin/icewm-session --nobg >/tmp/icewm.log 2>&1 9>&- &
/opt/selkies/bin/python /opt/scidesktop/desktop_scale.py watch >/tmp/desktop-scale.log 2>&1 9>&- &
echo "[desktop] IceWM session started"

# PulseAudio compatibility: selkies captures the monitor source.
export PIPEWIRE_RUNTIME_DIR="${XDG_RUNTIME_DIR}"
export PULSE_RUNTIME_PATH="${XDG_RUNTIME_DIR}/pulse"
export PULSE_SERVER="unix:${PULSE_RUNTIME_PATH}/native"
mkdir -p "${PULSE_RUNTIME_PATH}"

# The session's bus and audio server, for applications started from outside
# the session (desktop_app.py).
printf '%s\n' "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS}" \
    "PULSE_SERVER=${PULSE_SERVER}" >"${XDG_RUNTIME_DIR}/desktop.env"

# Audio: PipeWire first; once its socket exists, the session manager and the
# PulseAudio server (which Selkies captures from) start together.
pipewire >/tmp/pipewire.log 2>&1 9>&- &
for _ in $(seq 1 100); do
    [ -S "${PIPEWIRE_RUNTIME_DIR}/pipewire-0" ] && break
    sleep 0.02
done
[ -S "${PIPEWIRE_RUNTIME_DIR}/pipewire-0" ] || echo "[desktop] WARNING: PipeWire socket not up after 2 s; see /tmp/pipewire.log" >&2
wireplumber >/tmp/wireplumber.log 2>&1 9>&- &
pipewire-pulse >/tmp/pipewire-pulse.log 2>&1 9>&- &
echo "[desktop] PipeWire started"

# Hold the lock while the X server runs (one from an earlier session that
# outlived its script is watched instead).
if [ -n "${xvfb_pid}" ]; then
    wait "${xvfb_pid}"
else
    while x_alive; do sleep 5; done
fi
echo "[desktop] X server gone; ending the session"
