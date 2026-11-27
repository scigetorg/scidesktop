# Interactive shell defaults: common listing aliases and flavour/version prompt.
# Lives in /etc/bash.bashrc.d so sessions on mounted or legacy home volumes
# still get `ll` and the clean prompt even when /home/jovyan/.bashrc is absent.
case $- in
    *i*) ;;
    *) return ;;
esac

if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Show `<flavour>-<version>:\w$ ` (omitting username and Kubernetes pod hostname).
if [ -n "${SCIDESKTOP_FLAVOUR:-}" ]; then
    _sd_label="${SCIDESKTOP_FLAVOUR}${SCIDESKTOP_VERSION:+-${SCIDESKTOP_VERSION}}"
    _sd_color=""
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        _sd_color=yes
    fi
    if [ "${_sd_color}" = yes ]; then
        PS1='\[\033[01;32m\]'"${_sd_label}"'\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
    else
        PS1="${_sd_label}"':\w\$ '
    fi
    case "${TERM:-}" in
        xterm*|rxvt*)
            PS1='\[\e]0;'"${_sd_label}"': \w\a\]'"${PS1}"
            ;;
    esac
    unset _sd_label _sd_color
fi
