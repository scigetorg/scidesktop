#!/bin/bash
# Interactive shell defaults: common listing aliases and flavour/version prompt.
# Lives in /etc/bash.bashrc.d so sessions on mounted or legacy home volumes
# still get `ll` and the clean prompt even when /home/jovyan/.bashrc is absent.
case $- in
    *i*) ;;
    *) return ;;
esac

if [ -x /usr/bin/dircolors ]; then
    if [ -r ~/.dircolors ]; then
        eval "$(dircolors -b ~/.dircolors)"
    else
        eval "$(dircolors -b)"
    fi
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
        _sd_ps1='\[\033[01;32m\]'"${_sd_label}"'\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
    else
        _sd_ps1="${_sd_label}"':\w\$ '
    fi
    case "${TERM:-}" in
        xterm*|rxvt*)
            _sd_ps1='\[\e]0;'"${_sd_label}"': \w\a\]'"${_sd_ps1}"
            ;;
    esac
    PS1="${_sd_ps1}"
    _SCIDESKTOP_DEFAULT_PS1="${_sd_ps1}"
    unset _sd_label _sd_color _sd_ps1

    # On an existing PVC carrying an older unmodified Ubuntu ~/.bashrc, that
    # file runs after /etc/bash.bashrc.d and overwrites PS1 with \u@\h. Run a
    # one-shot PROMPT_COMMAND hook after ~/.bashrc finishes: replace only the
    # exact stock Ubuntu PS1 patterns while preserving any custom user PS1.
    _scidesktop_prompt_init() {
        local _sd_cur="${PS1:-}"
        local _sd_title_expanded='\[\e]0;\u@\h: \w\a\]'
        local _sd_title_literal='\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]'
        _sd_cur="${_sd_cur#"${_sd_title_expanded}"}"
        _sd_cur="${_sd_cur#"${_sd_title_literal}"}"
        case "${_sd_cur}" in
            '${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ ' | \
            '${debian_chroot:+($debian_chroot)}\u@\h:\w\$ ')
                PS1="${_SCIDESKTOP_DEFAULT_PS1}"
                ;;
        esac
        # Remove this one-shot hook from PROMPT_COMMAND (array or string).
        if declare -p PROMPT_COMMAND 2>/dev/null | grep -q 'declare -a'; then
            local -a _sd_next=()
            local _sd_item
            for _sd_item in "${PROMPT_COMMAND[@]}"; do
                [ "${_sd_item}" = "_scidesktop_prompt_init" ] || _sd_next+=("${_sd_item}")
            done
            PROMPT_COMMAND=("${_sd_next[@]}")
        else
            # Bash 5.1+ allows PROMPT_COMMAND to be either an array or a scalar string.
            # shellcheck disable=SC2178,SC2128
            PROMPT_COMMAND="${PROMPT_COMMAND//_scidesktop_prompt_init; /}"
            # shellcheck disable=SC2178,SC2128
            PROMPT_COMMAND="${PROMPT_COMMAND//; _scidesktop_prompt_init/}"
            # shellcheck disable=SC2178,SC2128
            PROMPT_COMMAND="${PROMPT_COMMAND//_scidesktop_prompt_init/}"
        fi
        unset -f _scidesktop_prompt_init
        unset _SCIDESKTOP_DEFAULT_PS1
    }

    if declare -p PROMPT_COMMAND 2>/dev/null | grep -q 'declare -a'; then
        PROMPT_COMMAND=(_scidesktop_prompt_init "${PROMPT_COMMAND[@]}")
    elif [ -n "${PROMPT_COMMAND:-}" ]; then
        # shellcheck disable=SC2178,SC2128
        PROMPT_COMMAND="_scidesktop_prompt_init; ${PROMPT_COMMAND}"
    else
        # shellcheck disable=SC2178
        PROMPT_COMMAND="_scidesktop_prompt_init"
    fi
fi
