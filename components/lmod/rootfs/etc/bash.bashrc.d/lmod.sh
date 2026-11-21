# Lmod in interactive shells that are not login shells (the desktop
# terminals); login shells get it from /etc/profile.d.
if ! shopt -q login_shell; then
    type -t module >/dev/null 2>&1 || . /etc/profile.d/z00_lmod.sh
    . /etc/profile.d/z01_lmod_modulepath.sh
fi
