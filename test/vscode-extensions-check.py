#!/usr/bin/env python3
"""Checks the VS Code extensions a component installs for every user, in the
image or on the OS layer with code-server. Called by the component's test
and by vscode-extensions-smoke.sh, with the Jupyter environment's Python.

    vscode-extensions-check.py <component>

For each extension the component's manifest entry names: it is in
code-server's system extensions folder at that version, readable by the user
and not writable, and its own manifest accepts this code-server's VS Code.
The folder still holds every extension of the code-server release.
"""

import json
import os
import re
import sys
from pathlib import Path

COMPONENT = sys.argv[1]
SYSTEM = Path("/usr/local/share/code-server/extensions")
BUNDLED = Path("/opt/code-server/lib/vscode/extensions")
FAILED = 0


def check(passed, message, detail=""):
    global FAILED
    if passed:
        print(f"  ok    {message}")
    else:
        FAILED += 1
        print(f"  FAIL  {message}{': ' + str(detail)[:300] if detail != '' else ''}")
    return passed


def version_tuple(text):
    return tuple(int(part) for part in re.findall(r"\d+", text)[:3])


def accepts(engine, vscode):
    """Whether a package.json `engines.vscode` range admits this VS Code."""
    if engine in ("*", ""):
        return True
    wanted = version_tuple(engine)
    have = version_tuple(vscode)
    if engine.startswith("^"):
        return have[0] == wanted[0] and have >= wanted
    return have >= wanted


vscode = json.loads((BUNDLED.parent / "package.json").read_text())["version"]
expected = json.loads(Path(f"/opt/scidesktop/manifest.d/{COMPONENT}.json").read_text())
check(len(expected) > 0, f"{COMPONENT} names {len(expected)} extensions")
for identifier, version in sorted(expected.items()):
    folder = SYSTEM / f"{identifier}-{version}"
    try:
        package = json.loads((folder / "package.json").read_text())
    except (OSError, ValueError) as error:
        check(False, f"{identifier} {version} is installed", error)
        continue
    name = f"{package.get('publisher', '')}.{package.get('name', '')}".lower()
    engine = package.get("engines", {}).get("vscode", "")
    check(name == identifier and package.get("version") == version and accepts(engine, vscode),
          f"{identifier} {version} is installed and accepts VS Code {vscode}", f"{name} {package.get('version')} {engine}")
    writable = [str(path) for path in [folder, *folder.rglob("*")] if not path.is_symlink() and os.access(path, os.W_OK)]
    unreadable = [str(path) for path in folder.rglob("*") if not path.is_symlink() and not os.access(path, os.R_OK)]
    check(not writable and not unreadable, f"{identifier} is readable by the user and not writable",
          (writable or unreadable)[:3])

missing = sorted(set(os.listdir(BUNDLED)) - set(os.listdir(SYSTEM)))
check(not missing, "the folder still holds every extension of the code-server release", missing[:5])

sys.exit(1 if FAILED else 0)
