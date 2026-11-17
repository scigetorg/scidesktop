# Tell the user, once per terminal, when containerised tools cannot run here
# (written at startup by before-notebook.d/10-apptainer).
if [ -r /tmp/.scidesktop-containers-unavailable ]; then
    printf '\033[1;33m%s\033[0m\n' "$(cat /tmp/.scidesktop-containers-unavailable)" >&2
fi
