#!/bin/bash
# The contract every OS layer (components/os-*) must meet. Checks behaviour,
# not package names, so the same script runs against any distribution.
set -uo pipefail
FAILED=0
check() {
    local what="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf '  ok    %s\n' "${what}"
    else
        printf '  FAIL  %s\n' "${what}"; FAILED=$((FAILED + 1))
    fi
}
has() { command -v "$1"; }
lib() { ldconfig -p | grep -q "$1"; }

echo "os-contract: $(. /etc/os-release && echo "${PRETTY_NAME}") $(uname -m)"

# core
for b in bash curl sudo tini usermod groupmod useradd locale-gen; do check "core: ${b}" has "${b}"; done
check "core: CA bundle" test -s /etc/ssl/certs/ca-certificates.crt

# locale
check "locale: C.UTF-8" bash -c 'LC_ALL=C.UTF-8 locale 2>&1 | grep -qv "Cannot set"'
check "locale: en_US.UTF-8" bash -c 'locale -a | grep -qi "en_US.utf8"'

# user
check "user: ${NB_USER:-jovyan} is UID 1000" test "$(id -u "${NB_USER:-jovyan}")" = 1000
check "user: primary group GID 100" test "$(id -g "${NB_USER:-jovyan}")" = 100
check "user: home exists and is owned" test -O "/home/${NB_USER:-jovyan}" -o "$(stat -c %u "/home/${NB_USER:-jovyan}")" = 1000
check "user: /etc/passwd group-writable" bash -c '[ "$(stat -c %A /etc/passwd | cut -c6)" = w ]'

# x11
for b in Xvfb xrandr cvt dbus-launch; do check "x11: ${b}" has "${b}"; done
for l in libX11-xcb.so libXtst.so libXfixes.so libXdamage.so libxkbcommon.so; do check "x11: ${l}" lib "${l}"; done

# gl
for l in libGL.so libEGL.so libGLESv2.so libdrm.so libva.so libva-drm.so libva-x11.so; do check "gl: ${l}" lib "${l}"; done

# desktop
for b in icewm-session icewm thunar xfce4-terminal; do check "desktop: ${b}" has "${b}"; done
check "desktop: IceWM theme" test -f /etc/X11/icewm/themes/Arc-Dark/default.theme

# audio
for b in pipewire pipewire-pulse wireplumber; do check "audio: ${b}" has "${b}"; done
check "audio: libpulse" lib libpulse.so

# fuse and apptainer runtime
for b in fusermount3 squashfuse fuse-overlayfs newuidmap fakeroot; do check "fuse: ${b}" has "${b}"; done

# cvmfs
check "cvmfs: cvmfs2" has cvmfs2
check "cvmfs: mount helper" test -x /sbin/mount.cvmfs -o -x /usr/sbin/mount.cvmfs

# tools base components call (jupyterlab-git: git, ssh, an editor; tar -J: xz)
for b in git ssh nano xz tmux; do check "tools: ${b}" has "${b}"; done

# lmod runtime
check "lmod: lua5.4" has lua5.4
check "lmod: lua posix" lua5.4 -e 'require("posix")'
check "lmod: lua filesystem" lua5.4 -e 'require("lfs")'
check "lmod: tclsh" has tclsh

# pinning: packages were installed from a snapshot, recorded in the manifest;
# at runtime the package manager points at the live archive again
check "pinning: snapshot recorded in manifest" bash -c 'grep -q "\"package_snapshot\": \"[0-9]" /opt/scidesktop/manifest.d/os-*.json'
check "pinning: runtime sources are live" bash -c '! grep -rqs "snapshot\." /etc/apt/sources.list.d /etc/yum.repos.d'

# drop-in points other components rely on
check "shell: interactive bash sources /etc/bash.bashrc.d" bash -c 'grep -qs "bash.bashrc.d" /etc/bash.bashrc /etc/bashrc'
check "hooks: CVMFS startup hook" test -x /usr/local/bin/before-notebook.d/20-cvmfs

# nothing a desktop image should not carry
check "no development headers" bash -c '! ls /usr/include/qt*/QtCore /usr/include/glib-2.0 2>/dev/null | grep -q .'

if [ "${FAILED}" -gt 0 ]; then
    echo "os-contract: ${FAILED} check(s) failed"; exit 1
fi
echo "os-contract: all checks passed"
