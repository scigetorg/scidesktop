# The `t3` command in a terminal uses the image's relay client for T3
# Connect, as the session's T3 Code does
# (/etc/scidesktop/t3-code/environment.d/50-t3-connect.json), instead of
# offering to download one into the home. Login shells read this file; other
# interactive shells get it from /etc/bash.bashrc.d.
if [ -z "${T3CODE_CLOUDFLARED_PATH:-}" ]; then
    export T3CODE_CLOUDFLARED_PATH=/opt/t3-connect/bin/cloudflared
fi
if [ -z "${TUNNEL_METRICS:-}" ]; then
    export TUNNEL_METRICS=127.0.0.1:0
fi
