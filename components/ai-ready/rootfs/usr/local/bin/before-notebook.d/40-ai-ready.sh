#!/bin/bash
# Starts the AI Ready services (PostgreSQL, MLflow, Airflow) beside the
# notebook server and tells notebooks where MLflow is. start.sh sources this
# file, so the exports reach Jupyter, its kernels and its terminals.
#
# The services run under a supervisor (ai_ready_services.py) that stays in
# this shell's process group: when the container stops, tini signals the
# group and the supervisor shuts the services down in order.

_ai_ready=(/opt/ai-ready/env/bin/python /opt/ai-ready/lib/ai_ready_services.py)

# The supervisor owns these values; nothing is repeated here.
eval "$("${_ai_ready[@]}" env)"

if [ "$(id -u)" -eq 0 ]; then
    # Started as root: run as the notebook user, like the server will. setpriv
    # replaces itself with the command. runuser would stay in front of it and
    # kill it two seconds after a SIGTERM, before PostgreSQL has shut down.
    _ai_ready=(setpriv --reuid "${NB_USER}" --regid "$(id -g "${NB_USER}")" --init-groups
        env "HOME=$(getent passwd "${NB_USER}" | cut -d: -f6)" "USER=${NB_USER}" "${_ai_ready[@]}")
fi
"${_ai_ready[@]}" run </dev/null &
# The notebook server waits for this process when it exits
# (/etc/scidesktop/jupyter_server_config.d/ai-ready.py).
export AI_READY_SUPERVISOR_PID=$!
echo "[ai-ready] services starting in the background (PID ${AI_READY_SUPERVISOR_PID})"
unset _ai_ready
