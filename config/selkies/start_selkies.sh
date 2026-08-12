#!/bin/bash
# Selkies launcher, spawned by jupyter-server-proxy on the first /desktop hit.
# Serves the web UI, signalling, video, audio and input on one port, bound to
# loopback behind the Jupyter proxy.
#
# Usage: start_selkies.sh <port> <subfolder>
#   port      allocated by jupyter-server-proxy ({port})
#   subfolder URL prefix we are proxied under; needs both slashes

set -euo pipefail

PORT="${1:?port argument required}"
SUBFOLDER="${2:-}"

export DISPLAY="${DISPLAY:-:20}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
export PULSE_RUNTIME_PATH="${XDG_RUNTIME_DIR}/pulse"
export PULSE_SERVER="unix:${PULSE_RUNTIME_PATH}/native"

# Strip any ".screen" suffix: DISPLAY=:20.0 would look for X20.0.
DISPLAY_NUM="${DISPLAY#*:}"
X_SOCKET="/tmp/.X11-unix/X${DISPLAY_NUM%%.*}"

# Start the session and let it come up while selkies starts.
if [ ! -S "${X_SOCKET}" ]; then
    echo "[selkies] starting desktop session"
    setsid /opt/scidesktop/start_desktop.sh </dev/null >>/tmp/scidesktop-desktop.log 2>&1 &
fi

for _ in $(seq 1 200); do
    [ -S "${X_SOCKET}" ] && break
    sleep 0.3
done

if [ ! -S "${X_SOCKET}" ]; then
    echo "[selkies] ERROR: no X server at ${X_SOCKET}; see /tmp/Xvfb.log and /tmp/scidesktop-desktop.log" >&2
    exit 1
fi

echo "[selkies] starting on 127.0.0.1:${PORT} under '${SUBFOLDER:-/}'"

# Selkies refuses to start without a password; the Jupyter config generates one
# per container and the proxy sends the matching header.
exec selkies \
    --addr=127.0.0.1 \
    --port="${PORT}" \
    ${SUBFOLDER:+--subfolder="${SUBFOLDER}"} \
    --basic-auth-user="${SELKIES_BASIC_AUTH_USER:-${NB_USER:-jovyan}}"
