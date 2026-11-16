# Lmod in interactive shells that are not login shells (the desktop and
# JupyterLab terminals); login shells get it from /etc/profile.d.
if ! shopt -q login_shell && ! type -t module >/dev/null 2>&1; then
    . /etc/profile.d/z00_lmod.sh
fi
