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

    for _ in $(seq 1 100); do
        [ -S "${X_SOCKET}" ] && break
        sleep 0.3
    done
fi

if [ ! -S "${X_SOCKET}" ]; then
    echo "[desktop] ERROR: X server did not start; see /tmp/Xvfb.log" >&2
    exit 1
fi
echo "[desktop] Xvfb ready on ${DISPLAY}"

/usr/bin/dbus-launch --exit-with-session /usr/bin/startlxqt >/tmp/lxqt.log 2>&1 &
echo "[desktop] LXQt session started"

# PulseAudio compatibility: selkies captures the monitor source.
export PIPEWIRE_RUNTIME_DIR="${XDG_RUNTIME_DIR}"
export PULSE_RUNTIME_PATH="${XDG_RUNTIME_DIR}/pulse"
export PULSE_SERVER="unix:${PULSE_RUNTIME_PATH}/native"
mkdir -p "${PULSE_RUNTIME_PATH}"

pipewire >/tmp/pipewire.log 2>&1 &
sleep 1
wireplumber >/tmp/wireplumber.log 2>&1 &
sleep 0.3
pipewire-pulse >/tmp/pipewire-pulse.log 2>&1 &
echo "[desktop] PipeWire ready"

wait
