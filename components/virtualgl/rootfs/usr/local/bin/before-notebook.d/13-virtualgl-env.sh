# Sourced by start.sh: configure VirtualGL's EGL back end for GPU-accelerated
# OpenGL on Xvfb (used by both native apps and containerized tools via
# `vglrun`). Explicit VGL_DISPLAY values are kept.
#
# VirtualGL 3.1.5 matches VGL_DISPLAY paths against EGL_DRM_DEVICE_FILE_EXT
# (the primary DRM /dev/dri/cardN node, not /dev/dri/by-path symlinks or
# render-only nodes). VMs often expose a virtual GPU card alongside an NVIDIA
# GPU, so select only an NVIDIA DRM card node and fall back to "egl" only when
# an NVIDIA GPU device is exposed without a matching card node.
#
# APPTAINERENV_VGL_DISPLAY propagates VGL_DISPLAY into Apptainer containers
# even when sciget runs them with --cleanenv.
#
# SCIDESKTOP_SYS_ROOT, SCIDESKTOP_DEV_ROOT, SCIDESKTOP_PROC_ROOT allow
# overriding /sys, /dev and /proc in tests.
_vgl_sys="${SCIDESKTOP_SYS_ROOT:-/sys}"
_vgl_dev="${SCIDESKTOP_DEV_ROOT:-/dev}"
_vgl_proc="${SCIDESKTOP_PROC_ROOT:-/proc}"

if [ -z "${VGL_DISPLAY:-}" ]; then
    _vgl_found=""
    # 1. Preferred: match the NVIDIA PCI device's primary DRM card via by-path.
    for _vgl_pci_dir in "${_vgl_sys}"/bus/pci/drivers/nvidia/[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]:*; do
        [ -e "${_vgl_pci_dir}" ] || continue
        _vgl_pci="$(basename "${_vgl_pci_dir}")"
        _vgl_link="${_vgl_dev}/dri/by-path/pci-${_vgl_pci}-card"
        if [ -e "${_vgl_link}" ]; then
            _vgl_real="$(readlink -f "${_vgl_link}" 2>/dev/null || true)"
            if [ -n "${_vgl_real}" ] && [ -r "${_vgl_real}" ]; then
                _vgl_found="${_vgl_real}"
                break
            fi
        fi
    done
    # 2. Fallback when /dev/dri/by-path is absent (common in containers):
    # match only a primary /dev/dri/cardN whose sysfs device is NVIDIA
    # (driver "nvidia" or PCI vendor 0x10de), ignoring virtual GPUs.
    if [ -z "${_vgl_found}" ]; then
        for _vgl_drm in "${_vgl_sys}"/class/drm/card[0-9]*; do
            [ -e "${_vgl_drm}" ] || continue
            _vgl_name="$(basename "${_vgl_drm}")"
            case "${_vgl_name}" in
                *-*) continue ;;
            esac
            _vgl_is_nv=""
            if [ -e "${_vgl_drm}/device/driver" ]; then
                _vgl_drv="$(basename "$(readlink -f "${_vgl_drm}/device/driver" 2>/dev/null || true)")"
                [ "${_vgl_drv}" = "nvidia" ] && _vgl_is_nv=1
            fi
            if [ -z "${_vgl_is_nv}" ] && [ -r "${_vgl_drm}/device/vendor" ]; then
                _vgl_vendor="$(tr 'A-Z' 'a-z' < "${_vgl_drm}/device/vendor" 2>/dev/null | tr -d '[:space:]')"
                [ "${_vgl_vendor}" = "0x10de" ] && _vgl_is_nv=1
            fi
            if [ -n "${_vgl_is_nv}" ] && [ -r "${_vgl_dev}/dri/${_vgl_name}" ]; then
                _vgl_found="$(readlink -f "${_vgl_dev}/dri/${_vgl_name}" 2>/dev/null || printf '%s' "${_vgl_dev}/dri/${_vgl_name}")"
                break
            fi
        done
    fi
    # 3. Last resort when the NVIDIA driver is loaded and an NVIDIA GPU device
    # is exposed to the container without a matching /dev/dri/cardN node.
    # Never trigger on /proc/driver/nvidia/version alone, which can be visible
    # in CPU-only containers on an NVIDIA host.
    if [ -z "${_vgl_found}" ] && [ -f "${_vgl_proc}/driver/nvidia/version" ] && [ -r "${_vgl_dev}/nvidiactl" ]; then
        for _vgl_nvdev in "${_vgl_dev}"/nvidia[0-9]*; do
            if [ -r "${_vgl_nvdev}" ]; then
                _vgl_found="egl"
                break
            fi
        done
    fi
    if [ -n "${_vgl_found}" ]; then
        export VGL_DISPLAY="${_vgl_found}"
    fi
    unset _vgl_found _vgl_pci_dir _vgl_pci _vgl_link _vgl_real _vgl_drm _vgl_name _vgl_is_nv _vgl_drv _vgl_vendor _vgl_nvdev
fi

if [ -n "${VGL_DISPLAY:-}" ] && [ -z "${APPTAINERENV_VGL_DISPLAY+x}" ]; then
    export APPTAINERENV_VGL_DISPLAY="${VGL_DISPLAY}"
fi

unset _vgl_sys _vgl_dev _vgl_proc
