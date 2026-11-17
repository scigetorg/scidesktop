#!/bin/bash
# Bring up the desktop session: Xvfb, LXQt, PipeWire.
# Called by start_selkies.sh on first use, not at container boot.

export DISPLAY="${DISPLAY:-:20}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"

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

# One D-Bus session for LXQt and the audio stack. Without an address in its
# environment PipeWire auto-launches its own bus through the X server, which
# can stall it for seconds and leave WirePlumber unable to connect.
eval "$(/usr/bin/dbus-launch --sh-syntax --exit-with-x11)"
export DBUS_SESSION_BUS_ADDRESS
/usr/bin/startlxqt >/tmp/lxqt.log 2>&1 &
echo "[desktop] LXQt session started"

# PulseAudio compatibility: selkies captures the monitor source.
export PIPEWIRE_RUNTIME_DIR="${XDG_RUNTIME_DIR}"
export PULSE_RUNTIME_PATH="${XDG_RUNTIME_DIR}/pulse"
export PULSE_SERVER="unix:${PULSE_RUNTIME_PATH}/native"
mkdir -p "${PULSE_RUNTIME_PATH}"

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
