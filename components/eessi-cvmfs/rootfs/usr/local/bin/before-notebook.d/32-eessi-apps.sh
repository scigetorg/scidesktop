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
    _eessi_cache="${EESSI_CACHE_DIR:-${_eessi_home}/.cache/scidesktop/eessi}"
    _eessi_env=("EESSI_CACHE_DIR=${_eessi_cache}")
    [ -n "${EESSI_CATALOG_FILES:-}" ] && _eessi_env+=("EESSI_CATALOG_FILES=${EESSI_CATALOG_FILES}")
    [ -n "${EESSI_CATALOG_URLS:-}" ] && _eessi_env+=("EESSI_CATALOG_URLS=${EESSI_CATALOG_URLS}")
    [ -n "${SCIGET_CATALOGS_FILE:-}" ] && _eessi_env+=("SCIGET_CATALOGS_FILE=${SCIGET_CATALOGS_FILE}")
    [ -n "${EESSI_STATIC_APPS_DIR:-}" ] && _eessi_env+=("EESSI_STATIC_APPS_DIR=${EESSI_STATIC_APPS_DIR}")

    if [ "${SCIDESKTOP_EESSI_CATALOG_REFRESH:-yes}" = yes ] && [ -x /usr/local/bin/eessi-catalog ]; then
        if [ "$(/usr/bin/id -u)" -eq 0 ]; then
            if [ -x /opt/scidesktop/run-as-user ]; then
                /opt/scidesktop/run-as-user /usr/bin/env "${_eessi_env[@]}" \
                    timeout 10 /usr/local/bin/eessi-catalog sync \
                    || echo "[eessi] catalog refresh failed; using cached or built-in launchers" >&2
            else
                /usr/bin/env "HOME=${_eessi_home}" "USER=${_eessi_user}" "${_eessi_env[@]}" \
                    /usr/bin/setpriv \
                    --reuid "$(/usr/bin/id -u "${_eessi_user}")" --regid "$(/usr/bin/id -g "${_eessi_user}")" \
                    --init-groups --no-new-privs --inh-caps -all --ambient-caps -all -- \
                    timeout 10 /usr/local/bin/eessi-catalog sync \
                    || echo "[eessi] catalog refresh failed; using cached or built-in launchers" >&2
            fi
        else
            /usr/bin/env "${_eessi_env[@]}" timeout 10 /usr/local/bin/eessi-catalog sync \
                || echo "[eessi] catalog refresh failed; using cached or built-in launchers" >&2
        fi
    fi

    _eessi_selected_dir=""
    if [ -x /usr/local/bin/eessi-catalog ]; then
        _eessi_selected_dir="$(/usr/bin/env "${_eessi_env[@]}" /usr/local/bin/eessi-catalog apps-dir 2>/dev/null || true)"
    elif [ -d "${EESSI_STATIC_APPS_DIR:-/etc/scidesktop/eessi-apps.d}" ]; then
        _eessi_selected_dir="${EESSI_STATIC_APPS_DIR:-/etc/scidesktop/eessi-apps.d}"
    fi

    if [ -n "${_eessi_selected_dir}" ] && [ -d "${_eessi_selected_dir}" ]; then
        _eessi_app_dirs="${SCIDESKTOP_APP_DIRS:-/opt/sciget/applications}"
        case ":${_eessi_app_dirs}:" in
        *":${_eessi_selected_dir}:"*) ;;
        *) _eessi_app_dirs="${_eessi_app_dirs}:${_eessi_selected_dir}" ;;
        esac
        export SCIDESKTOP_APP_DIRS="${_eessi_app_dirs}"
    fi
    unset _eessi_user _eessi_home _eessi_cache _eessi_env _eessi_selected_dir _eessi_app_dirs
fi
