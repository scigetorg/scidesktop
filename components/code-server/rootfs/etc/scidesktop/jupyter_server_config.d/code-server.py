# code-server's part of the notebook server's configuration: the VS Code tile
# and the proxy entry behind it. code-server starts on first use and listens
# on a Unix socket only the user can open, so the notebook server's login is
# the only way to it; that is why its own login is off.
import os

c.ServerProxy.servers.update({  # noqa: F821
    "vscode": {
        "command": [
            "/opt/code-server/bin/code-server",
            "--auth", "none",
            "--disable-telemetry",
            "--disable-update-check",
            "--socket", "{unix_socket}",
            "--socket-mode", "0600",
            os.environ.get("CODE_SERVER_WORKDIR") or os.path.expanduser("~"),
        ],
        "unix_socket": True,
        "timeout": 60,
        "new_browser_tab": True,
        "launcher_entry": {
            "path_info": "vscode",
            "title": "VS Code",
            "icon_path": "/opt/code-server/src/browser/media/favicon.svg",
            "category": "Scidesktop",
        },
    }
})
