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
# A server that answers, not just its socket: a container restart leaves the
# socket behind with no server (start_desktop.sh removes it).
x_alive() { [ -S "${X_SOCKET}" ] && xrdb -query >/dev/null 2>&1; }
# The session has set its starting resources (start_desktop.sh), which
# Selkies reads at start.
session_ready() { xrdb -query 2>/dev/null | grep -q '^Xft\.dpi:'; }

# Start the session if it is not running and wait for it. Selkies starts
# while the rest of the session (IceWM, audio) comes up.
start_session() {
    if ! x_alive; then
        echo "[selkies] starting desktop session"
        setsid /opt/scidesktop/start_desktop.sh </dev/null >>/tmp/scidesktop-desktop.log 2>&1 &
    fi
    # Up to 60 s, checked often: jupyter-server-proxy re-checks readiness at
    # doubling intervals (~1.3 s, then ~2.6 s), so starting Selkies sooner
    # can save a whole interval.
    for _ in $(seq 1 1200); do
        x_alive && session_ready && break
        sleep 0.05
    done
    if ! x_alive; then
        echo "[selkies] ERROR: no X server at ${X_SOCKET}; see /tmp/Xvfb.log and /tmp/scidesktop-desktop.log" >&2
        return 1
    fi
}

# The pointer size at 96 DPI; Selkies scales it with the DPI it sets from the
# browser (start_desktop.sh sets the same size before any browser connects).
export SELKIES_CURSOR_SIZE="${SELKIES_CURSOR_SIZE:-24}"

# jupyter-server-proxy starts this once and never again, even after it exits,
# so it stays up and keeps the desktop serving: Selkies outlives a dead X
# server, and a session whose X server dies (or a Selkies that exits) is
# replaced with a new one on the same port.
selkies_pid=
trap '[ -z "${selkies_pid}" ] || kill "${selkies_pid}" 2>/dev/null; exit 0' TERM INT HUP
start_session || exit 1
while true; do
    echo "[selkies] starting on 127.0.0.1:${PORT} under '${SUBFOLDER:-/}'"
    # Selkies refuses to start without a password; the Jupyter config
    # generates one per container and the proxy sends the matching header.
    selkies \
        --addr=127.0.0.1 \
        --port="${PORT}" \
        ${SUBFOLDER:+--subfolder="${SUBFOLDER}"} \
        --basic-auth-user="${SELKIES_BASIC_AUTH_USER:-${NB_USER:-jovyan}}" &
    selkies_pid=$!
    while kill -0 "${selkies_pid}" 2>/dev/null && x_alive; do
        sleep 2
    done
    if kill -0 "${selkies_pid}" 2>/dev/null; then
        echo "[selkies] X server gone; restarting the desktop"
        kill "${selkies_pid}" 2>/dev/null || true
    else
        echo "[selkies] Selkies exited; restarting it" >&2
    fi
    wait "${selkies_pid}" || true
    selkies_pid=
    sleep 1
    until start_session; do sleep 5; done
done
