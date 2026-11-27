# The desktop's part of the notebook server's configuration: the Desktop tile
# and one tile per desktop application.
import base64
import os
import secrets

# Desktop credential, generated per container. The proxy injects the matching
# header, so the user never sees a login prompt.
_user = os.environ.get("NB_USER", "jovyan")
_password = os.environ.get("SELKIES_BASIC_AUTH_PASSWORD") or secrets.token_urlsafe(24)
_auth = base64.b64encode(f"{_user}:{_password}".encode()).decode()

# update() adds to the entries of other components; nothing here assigns the
# shared setting.
c.ServerProxy.servers.update({  # noqa: F821
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
            'icon_path': '/opt/scidesktop/desktop.svg',
            'category': 'Scidesktop',
        },
    }
})

# App mode: one launcher tile per desktop entry in SCIDESKTOP_APP_DIRS
# (default: the launchers sciget writes). A tile starts its application on the
# desktop display, maximised, and opens the stream (desktop_app.py). Entries
# are read when Jupyter starts.
import configparser
import glob
import re

_CATEGORY_MAP = {
    'X-ImageAnalysis': 'Image Analysis',
    'X-DataAccess': 'Data Access',
    'Science': 'Science',
    'Biology': 'Science',
    'Development': 'Development',
    'Graphics': 'Graphics',
    'Office': 'Office',
    'Education': 'Education',
    'System': 'System',
}


def _app_category(de):
    explicit = de.get("X-Scidesktop-Category", "").strip()
    if explicit:
        return explicit
    for cat in de.get("Categories", "").split(";"):
        mapped = _CATEGORY_MAP.get(cat.strip())
        if mapped:
            return mapped
    return 'Desktop applications'


def _app_entries():
    dirs = os.environ.get("SCIDESKTOP_APP_DIRS", "/opt/sciget/applications")
    for path in sorted(p for d in dirs.split(":") if d for p in glob.glob(f"{d}/*.desktop")):
        entry = configparser.ConfigParser(interpolation=None, strict=False)
        entry.optionxform = str
        try:
            entry.read(path)
            de = entry["Desktop Entry"]
        except (configparser.Error, KeyError):
            continue
        if de.get("Type", "Application") != "Application" or not de.get("Exec") \
                or de.get("NoDisplay", "false") == "true" or de.get("Hidden", "false") == "true":
            continue
        name = "app-" + re.sub(r"[^a-z0-9-]+", "-", os.path.basename(path)[:-8].lower()).strip("-")
        icon = de.get("Icon", "")
        yield name, {
            'command': [
                '/opt/selkies/bin/python', '/opt/scidesktop/desktop_app.py',
                '{port}', '{base_url}desktop/', path,
            ],
            'timeout': 30,
            'launcher_entry': {
                'path_info': f'{name}/launch',
                'title': de.get("Name", name),
                'category': _app_category(de),
                **({'icon_path': icon} if icon.endswith(".svg") and os.path.isfile(icon) else {}),
            },
        }


c.ServerProxy.servers.update(dict(_app_entries()))  # noqa: F821
