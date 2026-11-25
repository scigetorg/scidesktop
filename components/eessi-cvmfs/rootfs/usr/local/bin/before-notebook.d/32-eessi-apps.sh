# shellcheck shell=bash
# Sourced by start.sh after 20-cvmfs and before Jupyter starts:
# refreshes curated EESSI catalog launchers (fail-soft) and exposes EESSI
# desktop launchers (live-synced cache or built-in /etc/scidesktop/eessi-apps.d
# fallback) to JupyterLab's launcher whenever /cvmfs/software.eessi.io is
# mounted and CVMFS is not disabled.
#
# SCIDESKTOP_EESSI_CATALOG_REFRESH: yes (default) | no
if [ "${SCIDESKTOP_CVMFS_MODE:-external}" != disabled ] \
    && ls "${EESSI_MODULE_ROOT:-/cvmfs/software.eessi.io/init/modules}" >/dev/null 2>&1; then
    if [ "$(/usr/bin/id -u)" -eq 0 ]; then
        _eessi_user="${NB_USER:-jovyan}"
        _eessi_home="$(/usr/bin/getent passwd "${_eessi_user}" | cut -d: -f6)"
    else
        _eessi_user=""
        _eessi_home="${HOME}"
    fi
    _eessi_xdg_cache="${XDG_CACHE_HOME:-${_eessi_home}/.cache}"
    _eessi_cache="${EESSI_CACHE_DIR:-${_eessi_xdg_cache}/scidesktop/eessi}"
    _eessi_static_dir="${EESSI_STATIC_APPS_DIR:-/etc/scidesktop/eessi-apps.d}"
    _eessi_env=("EESSI_CACHE_DIR=${_eessi_cache}")
    [ -n "${EESSI_CATALOG_FILES:-}" ] && _eessi_env+=("EESSI_CATALOG_FILES=${EESSI_CATALOG_FILES}")
    [ -n "${EESSI_CATALOG_URLS:-}" ] && _eessi_env+=("EESSI_CATALOG_URLS=${EESSI_CATALOG_URLS}")
    [ -n "${SCIGET_CATALOGS_FILE:-}" ] && _eessi_env+=("SCIGET_CATALOGS_FILE=${SCIGET_CATALOGS_FILE}")
    [ -n "${EESSI_STATIC_APPS_DIR:-}" ] && _eessi_env+=("EESSI_STATIC_APPS_DIR=${EESSI_STATIC_APPS_DIR}")
    [ -n "${EESSI_SESSION_APPS_ROOT:-}" ] && _eessi_env+=("EESSI_SESSION_APPS_ROOT=${EESSI_SESSION_APPS_ROOT}")

    # Helper runner that drops privileges to NB_USER when sourced as root so
    # root never reads or writes user-controlled cache paths.
    _eessi_run_cmd=()
    if [ "$(/usr/bin/id -u)" -eq 0 ]; then
        if [ -x /opt/scidesktop/run-as-user ]; then
            _eessi_run_cmd=(/opt/scidesktop/run-as-user /usr/bin/env "${_eessi_env[@]}")
        else
            _eessi_run_cmd=(
                /usr/bin/env "HOME=${_eessi_home}" "USER=${_eessi_user}" "${_eessi_env[@]}"
                /usr/bin/setpriv
                --reuid "$(/usr/bin/id -u "${_eessi_user}")" --regid "$(/usr/bin/id -g "${_eessi_user}")"
                --init-groups --no-new-privs --inh-caps -all --ambient-caps -all --
            )
        fi
    else
        _eessi_run_cmd=(/usr/bin/env "${_eessi_env[@]}")
    fi

    if [ "${SCIDESKTOP_EESSI_CATALOG_REFRESH:-yes}" = yes ] && [ -x /usr/local/bin/eessi-catalog ]; then
        "${_eessi_run_cmd[@]}" timeout 10 /usr/local/bin/eessi-catalog sync \
            || echo "[eessi] catalog refresh failed; using cached or built-in launchers" >&2
    fi

    _eessi_selected_dir=""
    if [ -x /usr/local/bin/eessi-catalog ]; then
        _eessi_selected_dir="$("${_eessi_run_cmd[@]}" timeout 5 /usr/local/bin/eessi-catalog session-apps-dir 2>/dev/null || true)"
    fi
    if [ -z "${_eessi_selected_dir}" ] && [ -d "${_eessi_static_dir}" ]; then
        _eessi_selected_dir="${_eessi_static_dir}"
    fi

    if [ -n "${_eessi_selected_dir}" ] && [ -d "${_eessi_selected_dir}" ]; then
        _eessi_app_dirs="${SCIDESKTOP_APP_DIRS:-/opt/sciget/applications}"
        case ":${_eessi_app_dirs}:" in
        *":${_eessi_selected_dir}:"*) ;;
        *) _eessi_app_dirs="${_eessi_app_dirs}:${_eessi_selected_dir}" ;;
        esac
        export SCIDESKTOP_APP_DIRS="${_eessi_app_dirs}"
    fi
    unset _eessi_user _eessi_home _eessi_xdg_cache _eessi_cache _eessi_static_dir _eessi_env _eessi_run_cmd _eessi_selected_dir _eessi_app_dirs
fi
