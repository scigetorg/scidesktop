#!/bin/bash
# Image hygiene & security baseline checks on a running container:
#   - no leftover apt package lists
#   - no sudo or Apptainer starter-suid
#   - security-sensitive Python server libraries above patched floors
#   - zero SUID/SGID binaries and zero POSIX file capabilities across /
#   - Jupyter server running with NoNewPrivs=1
#
#   ./test/hygiene-check.sh <container> [nb_user]

set -uo pipefail

NAME="${1:?usage: hygiene-check.sh <container> [nb_user]}"
NB_USER="${2:-jovyan}"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

if hygiene_err=$(docker exec -u 0 "${NAME}" /opt/conda/bin/python -c '
import errno, glob, importlib.metadata as im, os, re, stat
assert not glob.glob("/var/lib/apt/lists/*_Packages*"), "leftover apt package lists"
assert not os.path.exists("/usr/bin/sudo"), "sudo should not be installed"
assert not os.path.exists("/opt/apptainer/libexec/apptainer/bin/starter-suid"), "starter-suid should not be installed"
def ver(pkg, n=2):
    nums = [int(m.group(0)) for m in re.finditer(r"\d+", im.version(pkg))]
    return tuple(nums[:n])
assert ver("PyJWT") >= (2, 10), im.version("PyJWT")
assert ver("cryptography") >= (44, 0), im.version("cryptography")
assert ver("tornado") >= (6, 5), im.version("tornado")
assert ver("fastmcp", 3) >= (3, 4, 10), im.version("fastmcp")
root_dev = os.stat("/").st_dev
suid, caps = [], []
def onerror(err):
    if err.errno != errno.ENOENT:
        raise err
for root, dirs, files in os.walk("/", onerror=onerror):
    kept = []
    for d in dirs:
        dp = os.path.join(root, d)
        try:
            st = os.lstat(dp)
        except FileNotFoundError:
            continue
        if st.st_dev == root_dev and not stat.S_ISLNK(st.st_mode):
            kept.append(d)
    dirs[:] = kept
    for f in files:
        p = os.path.join(root, f)
        try:
            st = os.lstat(p)
        except FileNotFoundError:
            continue
        if not stat.S_ISREG(st.st_mode) or st.st_dev != root_dev:
            continue
        if st.st_mode & (stat.S_ISUID | stat.S_ISGID):
            suid.append(p)
        try:
            if "security.capability" in os.listxattr(p):
                caps.append(p)
        except OSError as exc:
            if exc.errno not in (errno.ENOENT, errno.EOPNOTSUPP):
                raise
assert not suid, f"unexpected SUID/SGID binaries: {suid}"
assert not caps, f"unexpected POSIX file capabilities: {caps}"
' 2>&1); then
    pass "image hygiene (no apt lists, zero SUID/SGID/file-caps, security package floors)"
else
    fail "image hygiene (no apt lists, zero SUID/SGID/file-caps, security package floors): ${hygiene_err}"
fi

docker exec -u "${NB_USER}" "${NAME}" sh -c '
    pid=$(pgrep -o -f "[j]upyter-lab|[j]upyter lab")
    [ -n "${pid}" ] && grep -qx "NoNewPrivs:[[:space:]]*1" "/proc/${pid}/status"
' 2>/dev/null \
    && pass "Jupyter server runs with NoNewPrivs=1" \
    || fail "Jupyter server runs with NoNewPrivs=1"

exit "${FAILED}"
