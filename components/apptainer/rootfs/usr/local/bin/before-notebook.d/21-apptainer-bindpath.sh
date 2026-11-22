# Sourced by start.sh AFTER 20-cvmfs: auto-populate APPTAINER_BINDPATH with
# actually-mounted, session-traversable generic host directories so containers
# see /data, mounted /mnt, and populated /cvmfs without failing on absent dirs
# or binding stock empty /mnt. Respects explicit APPTAINER_BIND,
# APPTAINER_BINDPATH (including empty "" opt-out), SINGULARITY_BIND, and
# SINGULARITY_BINDPATH.
if [ -z "${APPTAINER_BIND+x}" ] && [ -z "${APPTAINER_BINDPATH+x}" ] \
    && [ -z "${SINGULARITY_BIND+x}" ] && [ -z "${SINGULARITY_BINDPATH+x}" ]; then
    _apptainer_binds=""
    _apptainer_can_access() {
        local d="$1"
        [ -d "${d}" ] || return 1
        if [ "$(id -u)" -eq 0 ] && [ -x /opt/scidesktop/run-as-user ]; then
            /opt/scidesktop/run-as-user test -r "${d}" -a -x "${d}" 2>/dev/null
        else
            test -r "${d}" -a -x "${d}" 2>/dev/null
        fi
    }
    if _apptainer_can_access /data; then
        _apptainer_binds="${_apptainer_binds:+${_apptainer_binds},}/data"
    fi
    if _apptainer_can_access /mnt && { mountpoint -q /mnt 2>/dev/null || [ -n "$(ls -A /mnt 2>/dev/null)" ]; }; then
        _apptainer_binds="${_apptainer_binds:+${_apptainer_binds},}/mnt"
    fi
    if _apptainer_can_access /cvmfs && [ -n "$(ls -A /cvmfs 2>/dev/null)" ]; then
        _apptainer_binds="${_apptainer_binds:+${_apptainer_binds},}/cvmfs"
    fi
    [ -n "${_apptainer_binds}" ] && export APPTAINER_BINDPATH="${_apptainer_binds}"
    unset -f _apptainer_can_access
    unset _apptainer_binds
fi
