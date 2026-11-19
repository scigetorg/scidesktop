#!/bin/bash
# Bring up the desktop session: Xvfb, IceWM, PipeWire. IceWM gives a taskbar
# and maximised applications (settings in /etc/X11/icewm).
# Called by start_selkies.sh on first use, not at container boot.

export DISPLAY="${DISPLAY:-:20}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"

# One session per container. Selkies and the app tiles both start it on
# demand; a second caller exits while the first holds the lock (the session's
# processes inherit it).
exec 9>"${XDG_RUNTIME_DIR}/desktop.lock"
flock -n 9 || { echo "[desktop] session already starting"; exit 0; }

# Strip any ".screen" suffix: DISPLAY=:20.0 would look for X20.0.
DISPLAY_NUM="${DISPLAY#*:}"
X_SOCKET="/tmp/.X11-unix/X${DISPLAY_NUM%%.*}"

# Oversized screen leaves room for client-driven resize.
if [ ! -S "${X_SOCKET}" ]; then
    /usr/bin/Xvfb "${DISPLAY}" -screen 0 "${SCIDESKTOP_XVFB_SCREEN:-8192x4096x24}" \
        +extension COMPOSITE +extension DAMAGE +extension GLX \
        +extension RANDR +extension RENDER +extension MIT-SHM \
        +extension XFIXES +extension XTEST \
        +iglx +render -nolisten tcp -ac -noreset -shmem -s 0 -dpms \
        >/tmp/Xvfb.log 2>&1 &

    # Up to 30 s, checked often: the desktop route waits on this.
    for _ in $(seq 1 600); do
        [ -S "${X_SOCKET}" ] && break
        sleep 0.05
    done
fi

if [ ! -S "${X_SOCKET}" ]; then
    echo "[desktop] ERROR: X server did not start; see /tmp/Xvfb.log" >&2
    exit 1
fi
echo "[desktop] Xvfb ready on ${DISPLAY}"

# Without a size, Xcursor scales the pointer to the screen height (1/48), so
# the oversized virtual screen gets a 96 px pointer. As a server resource it
# applies to every client, including applications in containers; Selkies
# scales it with the DPI (SELKIES_CURSOR_SIZE in start_selkies.sh).
echo 'Xcursor.size: 24' | xrdb -merge

# One D-Bus session for the desktop and the audio stack. Without an address in
# its environment PipeWire auto-launches its own bus through the X server,
# which can stall it for seconds and leave WirePlumber unable to connect.
eval "$(/usr/bin/dbus-launch --sh-syntax --exit-with-x11)"
export DBUS_SESSION_BUS_ADDRESS
# GTK applications take their DPI from XSETTINGS. Selkies rewrites
# ~/.xsettingsd with the browser's DPI and signals xsettingsd; start at 96 DPI
# like the X resources, so a file left by an earlier session does not apply.
printf 'Xft/DPI %d\n' $((96 * 1024)) >"${HOME}/.xsettingsd"
xsettingsd >/tmp/xsettingsd.log 2>&1 &

# IceWM's pixel sizes follow the DPI Selkies sets from the browser: its
# configuration comes from a runtime folder that desktop_scale.py rewrites.
export ICEWM_PRIVCFG="${XDG_RUNTIME_DIR}/icewm"
/opt/selkies/bin/python /opt/scidesktop/desktop_scale.py setup
# Without icewmbg: painting the oversized screen's background delays Selkies'
# start by about 0.5 s.
/usr/bin/icewm-session --nobg >/tmp/icewm.log 2>&1 &
/opt/selkies/bin/python /opt/scidesktop/desktop_scale.py watch >/tmp/desktop-scale.log 2>&1 &
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
pipewire >/tmp/pipewire.log 2>&1 &
for _ in $(seq 1 100); do
    [ -S "${PIPEWIRE_RUNTIME_DIR}/pipewire-0" ] && break
    sleep 0.02
done
[ -S "${PIPEWIRE_RUNTIME_DIR}/pipewire-0" ] || echo "[desktop] WARNING: PipeWire socket not up after 2 s; see /tmp/pipewire.log" >&2
wireplumber >/tmp/wireplumber.log 2>&1 &
pipewire-pulse >/tmp/pipewire-pulse.log 2>&1 &
echo "[desktop] PipeWire started"

wait
