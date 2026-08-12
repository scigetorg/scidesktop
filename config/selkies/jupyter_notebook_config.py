import base64
import os
import secrets

# Desktop credential, generated per container. The proxy injects the matching
# header, so the user never sees a login prompt.
_user = os.environ.get("NB_USER", "jovyan")
_password = os.environ.get("SELKIES_BASIC_AUTH_PASSWORD") or secrets.token_urlsafe(24)
_auth = base64.b64encode(f"{_user}:{_password}".encode()).decode()

c.ServerProxy.servers = {
    'desktop': {
        # {port} is allocated by the proxy; {base_url} carries the JupyterHub
        # per-user prefix, which selkies applies via --subfolder.
        'command': [
            '/opt/scidesktop/start_selkies.sh',
            '{port}',
            '{base_url}desktop/',
        ],
        'timeout': 180,
        # selkies serves every route under --subfolder, so the proxy must
        # forward the prefix rather than stripping it to '/'.
        'absolute_url': True,
        'environment': {
            'SELKIES_BASIC_AUTH_USER': _user,
            'SELKIES_BASIC_AUTH_PASSWORD': _password,
        },
        'request_headers_override': {
            'Authorization': f'Basic {_auth}',
        },
        'launcher_entry': {
            'path_info': 'desktop',
            'title': 'Desktop',
            'category': 'Scidesktop',
        },
    }
}

c.FileContentsManager.allow_hidden = True
c.ServerApp.terminado_settings = {
    "shell_command": ["/bin/bash"]
}
