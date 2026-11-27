# Interactive shells that are not login shells (the desktop terminals).
. /etc/profile.d/scigethelpers-cli.sh

# Static tab completion for `scigethelpers` in interactive Bash sessions.
# No live discovery or subprocesses run here; keep word lists in sync with
# `scigethelpers --help` and `scigethelpers check --help` (tested in test.sh).
if [ -n "${BASH_VERSION:-}" ] && [[ $- == *i* ]]; then
    _scigethelpers_complete() {
        local cur="${COMP_WORDS[COMP_CWORD]}"
        local cmd="${COMP_WORDS[1]:-}"
        local sub="${COMP_WORDS[2]:-}"
        if [ "${COMP_CWORD}" -eq 1 ]; then
            mapfile -t COMPREPLY < <(compgen -W "cite kernel uv check info agent help --help --version" -- "${cur}")
            return 0
        fi
        case "${cmd}" in
            cite)
                mapfile -t COMPREPLY < <(compgen -W "--output --since --clear --status --json --no-clobber --help" -- "${cur}")
                ;;
            kernel)
                if [ "${COMP_CWORD}" -eq 2 ]; then
                    mapfile -t COMPREPLY < <(compgen -W "add list remove --help" -- "${cur}")
                elif [ "${sub}" = "list" ]; then
                    mapfile -t COMPREPLY < <(compgen -W "--json --help" -- "${cur}")
                elif [ "${sub}" = "add" ]; then
                    mapfile -t COMPREPLY < <(compgen -W "--python --help" -- "${cur}")
                fi
                ;;
            uv)
                if [ "${COMP_CWORD}" -eq 2 ]; then
                    mapfile -t COMPREPLY < <(compgen -W "init rebuild remove list --help" -- "${cur}")
                elif [ "${sub}" = "list" ]; then
                    mapfile -t COMPREPLY < <(compgen -W "--json --help" -- "${cur}")
                elif [ "${sub}" = "init" ] || [ "${sub}" = "rebuild" ] || [ "${sub}" = "remove" ]; then
                    mapfile -t COMPREPLY < <(compgen -d -- "${cur}")
                fi
                ;;
            check)
                mapfile -t COMPREPLY < <(compgen -W "cvmfs gpu slurm t3 --json --help" -- "${cur}")
                ;;
            info)
                mapfile -t COMPREPLY < <(compgen -W "--json --no-probes --help" -- "${cur}")
                ;;
            agent)
                if [ "${COMP_CWORD}" -eq 2 ]; then
                    mapfile -t COMPREPLY < <(compgen -W "preflight --help" -- "${cur}")
                elif [ "${sub}" = "preflight" ]; then
                    mapfile -t COMPREPLY < <(compgen -W "--json --cwd --help" -- "${cur}")
                fi
                ;;
            help)
                if [ "${COMP_CWORD}" -eq 2 ]; then
                    mapfile -t COMPREPLY < <(compgen -W "cite kernel uv check info agent" -- "${cur}")
                elif [ "${COMP_CWORD}" -eq 3 ] && [ "${sub}" = "agent" ]; then
                    mapfile -t COMPREPLY < <(compgen -W "preflight" -- "${cur}")
                fi
                ;;
        esac
    }
    complete -F _scigethelpers_complete scigethelpers
fi
