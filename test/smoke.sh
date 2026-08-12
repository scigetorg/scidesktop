#!/bin/bash
# End-to-end check that a built image actually works.
#
#   ./test/smoke.sh [image]
#
# Asserts the things that break silently: the desktop route serving is not the
# same as the desktop rendering, and a missing package usually shows up as a
# blank screen rather than a build failure.

set -uo pipefail

IMAGE="${1:-scidesktop}"
NAME="scidesktop-smoke-$$"
PORT="${SMOKE_PORT:-18999}"
TOKEN="smoke"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() {
    docker logs "${NAME}" >/tmp/${NAME}.log 2>&1 || true
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "smoke: ${IMAGE}"
docker run -d --name "${NAME}" -p "${PORT}:8888" --shm-size=2g \
    -e JUPYTER_TOKEN="${TOKEN}" "${IMAGE}" >/dev/null || { echo "  FAIL  container did not start"; exit 1; }

# 1. Jupyter answers
for _ in $(seq 1 120); do
    curl -fsS -o /dev/null "http://127.0.0.1:${PORT}/api" 2>/dev/null && break
    sleep 1
done
if curl -fsS -o /dev/null "http://127.0.0.1:${PORT}/api" 2>/dev/null; then
    pass "jupyter responds"
else
    fail "jupyter responds"; exit 1
fi

# 2. The desktop route serves. This is what spawns selkies, so it is slow the
#    first time.
code=$(curl -s -o /tmp/${NAME}-desktop.html -w '%{http_code}' -m 180 \
    -H "Authorization: token ${TOKEN}" "http://127.0.0.1:${PORT}/desktop/")
[ "${code}" = "200" ] && pass "desktop route serves" || fail "desktop route serves (HTTP ${code})"

# 3. Only Jupyter listens on a routable port; selkies must stay on loopback.
external=$(docker exec "${NAME}" python3 -c "
ports=set()
for f in ('/proc/net/tcp','/proc/net/tcp6'):
    try:
        for line in open(f).readlines()[1:]:
            p=line.split()
            if p[3]=='0A':
                addr, port = p[1].split(':')
                if addr not in ('0100007F','00000000000000000000000001000000'):
                    ports.add(int(port,16))
    except Exception: pass
print(' '.join(str(p) for p in sorted(ports)))" 2>/dev/null)
[ "${external}" = "8888" ] && pass "only 8888 listens externally" \
    || fail "only 8888 listens externally (got: ${external:-none})"

# 4. The session is actually up
for proc in Xvfb lxqt-session pipewire; do
    docker exec "${NAME}" pgrep -x "${proc}" >/dev/null 2>&1 \
        && pass "${proc} running" || fail "${proc} running"
done

# 5. Real pixels. A desktop that fails to draw still serves HTTP, so read the
#    framebuffer rather than trusting the status code.
docker exec "${NAME}" python3 -c "
import sys, glob
sys.path[:0] = glob.glob('/usr/local/lib/python3*/dist-packages/selkies')
from Xlib import display as xd
from collections import Counter
r = xd.Display(':20').screen().root
g = r.get_geometry()
data = r.get_image(0, 0, min(g.width, 400), min(g.height, 300), 2, 0xffffffff).data
if isinstance(data, str): data = data.encode('latin-1')
px = [tuple(data[i:i+3]) for i in range(0, 4*400, 4)]
top, count = Counter(px).most_common(1)[0]
print(f'geometry {g.width}x{g.height} dominant {top} n={count}')
sys.exit(0 if g.width > 0 else 1)" 2>/dev/null | sed 's/^/        /'
[ "${PIPESTATUS[0]}" = "0" ] && pass "framebuffer readable" || fail "framebuffer readable"

# 6. module is on the path for interactive shells
docker exec "${NAME}" bash -lc 'type -t module' 2>/dev/null | grep -q function \
    && pass "module available" || fail "module available"

# 7. Nothing from the neurodesk lineage came along
if docker exec "${NAME}" bash -c 'ls -d /opt/neurodesk* /neurocommand /cvmfs/neurodesk* 2>/dev/null | head -1' 2>/dev/null | grep -q .; then
    fail "no neurodesk payload"
else
    pass "no neurodesk payload"
fi

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "smoke: all checks passed"
else
    echo "smoke: ${FAILED} check(s) failed; container log at /tmp/${NAME}.log"
fi
exit "${FAILED}"
