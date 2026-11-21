# Starts the session's Slurm queue (/opt/slurm/bin/slurm-session) beside the
# notebook server. start.sh sources this file.
#
# The supervisor stays in this shell's process group: when the container
# stops, tini signals the group and the supervisor stops the daemons in
# order.
# The notebook server waits for it before it exits.
#
# SCIDESKTOP_SLURM: yes (default) | no
# A session that already has a cluster (SLURM_CONF names its configuration,
# as on an HPC login node) keeps it: nothing is started here.

if [ "${SCIDESKTOP_SLURM:-yes}" != yes ]; then
    :
elif [ -n "${SLURM_CONF:-}" ] && [ "${SLURM_CONF}" != /etc/slurm/slurm.conf ]; then
    echo "[slurm] SLURM_CONF=${SLURM_CONF} is set: using that cluster, not starting one"
else
    _slurm=(/opt/slurm/bin/slurm-session run)
    if [ "$(id -u)" -eq 0 ]; then
        # Started as root: run as the notebook user, like the server will.
        # setpriv replaces itself with the command, so signals reach it.
        # start.sh has given the account the UID and GID asked for (NB_UID,
        # NB_GID) by now; the queue's directories still have the image's.
        _nb_user="${NB_USER:-jovyan}"
        chown -R "$(id -u "${_nb_user}"):$(id -g "${_nb_user}")" /run/slurm /run/slurmctld
        _slurm=(setpriv --reuid "${_nb_user}" --regid "$(id -g "${_nb_user}")" --init-groups
            env "HOME=$(getent passwd "${_nb_user}" | cut -d: -f6)" "USER=${_nb_user}" "${_slurm[@]}")
        unset _nb_user
    fi
    "${_slurm[@]}" </dev/null &
    # The notebook server waits for this process when it exits
    # (/etc/scidesktop/jupyter_server_config.d/slurm.py).
    export SCIDESKTOP_SLURM_SUPERVISOR_PID=$!
    echo "[slurm] starting the queue in the background (PID ${SCIDESKTOP_SLURM_SUPERVISOR_PID})"
    unset _slurm
fi
