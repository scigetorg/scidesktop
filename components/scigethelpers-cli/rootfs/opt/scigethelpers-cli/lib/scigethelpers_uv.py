#!/opt/conda/bin/python3 -I
"""Manage opt-in project-local uv notebook kernels.

Generalized from neurodesk/neurodesktop (config/jupyter/uv_kernel_prototype.py,
MIT, Copyright (c) 2021 NeuroDesk; /opt/scigethelpers-cli/LICENSE) for all
scidesktop images.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import pwd
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

MARKER = "scigethelpers_uv"


def clean_environment() -> dict[str, str]:
    return {
        key: value
        for key, value in os.environ.items()
        if key not in {"PYTHONPATH", "PYTHONHOME", "VIRTUAL_ENV"}
        and not key.startswith("CONDA_")
    }


def kernel_name(project: Path) -> str:
    slug = re.sub(r"[^a-z0-9_-]+", "-", project.name.lower()).strip("-") or "project"
    digest = hashlib.sha256(os.fsencode(project)).hexdigest()[:12]
    return f"scigethelpers-uv-{slug[:40]}-{digest}"


def atomic_json(path: Path, data: dict) -> None:
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".uv-kernel-")
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(data, stream, indent=2)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def read_marker(project: Path) -> dict:
    for directory in (project, project / ".venv"):
        marker = directory / f".{MARKER}.json"
        if marker.is_file():
            data = json.loads(marker.read_text())
            if not isinstance(data, dict) or not isinstance(data.get("project"), str):
                raise ValueError(f"Invalid uv kernel ownership record: {marker}")
            return data
    return {}


def is_uv_environment(venv: Path) -> bool:
    config = venv / "pyvenv.cfg"
    return config.is_file() and bool(re.search(r"^uv\s*=", config.read_text(), re.MULTILINE))


def launch(project: Path, arguments: list[str]) -> None:
    venv = project / ".venv"
    if read_marker(project).get("project") != str(project) or not (venv / "bin/python").is_file():
        raise ValueError(
            f"Environment missing or moved. Run: scigethelpers uv rebuild {str(project)!r}"
        )
    env = clean_environment()
    env["VIRTUAL_ENV"] = str(venv)
    env["PATH"] = str(venv / "bin") + os.pathsep + env.get("PATH", "")
    env["PYTHONNOUSERSITE"] = "1"
    os.execve(
        venv / "bin/python",
        [str(venv / "bin/python"), "-m", "ipykernel_launcher", *arguments],
        env,
    )


def safe_home() -> Path | None:
    env_home = os.environ.get("HOME")
    if env_home and env_home.strip():
        return Path(env_home).resolve()
    try:
        pw_dir = pwd.getpwuid(os.geteuid()).pw_dir
        if pw_dir:
            return Path(pw_dir).resolve()
    except KeyError:
        pass
    return None


def prepare(project: Path, command: str) -> None:
    from jupyter_core.paths import jupyter_data_dir

    if os.geteuid() == 0:
        raise ValueError("Run as the notebook user, not root.")
    forbidden = {Path("/")}
    home = safe_home()
    if home is not None:
        forbidden.add(home)
    if project in forbidden or os.path.ismount(project):
        raise ValueError("Choose an analysis subfolder, not a home or mount root.")
    if command != "remove" and not project.is_dir():
        raise ValueError("Create the analysis folder first.")
    root = Path(jupyter_data_dir()) / "kernels"
    root.mkdir(parents=True, exist_ok=True)
    with (root / f".{MARKER}.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        spec_dir = root / kernel_name(project)
        target = spec_dir / "kernel.json"
        if spec_dir.is_symlink():
            raise ValueError("Refusing a symlinked kernelspec directory.")
        registered = False
        if command == "remove" and not target.is_file():
            raise ValueError(f"No uv kernel registration for {project}")
        if spec_dir.exists():
            if not target.is_file():
                raise ValueError(f"Incomplete kernel registration at {spec_dir}; leaving it untouched.")
            existing = json.loads(target.read_text())
            if existing.get("metadata", {}).get(MARKER) != {"project": str(project)}:
                raise ValueError("Refusing to replace a kernel owned by another tool.")
            registered = True
        if command == "remove":
            shutil.rmtree(spec_dir)
            print("Removed registration; project files and environment retained.")
            return
        for parent in project.parents:
            manifest = parent / "pyproject.toml"
            if manifest.is_file():
                data = tomllib.loads(manifest.read_text())
                if "workspace" in data.get("tool", {}).get("uv", {}):
                    raise ValueError("Folders inside uv workspaces are not supported.")
        manifest = project / "pyproject.toml"
        data = tomllib.loads(manifest.read_text()) if manifest.exists() else {}
        if "workspace" in data.get("tool", {}).get("uv", {}):
            raise ValueError("uv workspaces are not supported.")
        venv = project / ".venv"
        if venv.is_symlink():
            raise ValueError("Refusing a symlinked .venv.")
        marker = read_marker(project)
        if venv.exists() and (not (marker or registered) or not is_uv_environment(venv)):
            raise ValueError("Existing .venv is unmanaged; use a fresh analysis folder.")
        if marker and marker.get("project") != str(project) and command != "rebuild":
            raise ValueError("Project moved; run rebuild after shutting down its kernels.")
        uv = shutil.which("uv")
        if not uv:
            raise ValueError("uv is required on PATH.")
        env = clean_environment()
        env["UV_PROJECT_ENVIRONMENT"] = str(venv)
        env["UV_LINK_MODE"] = "copy"

        def run(*arguments: str) -> None:
            location = "--directory" if arguments[0] == "init" else "--project"
            subprocess.run([uv, *arguments, location, str(project)], cwd=project, env=env, check=True)

        backup_venv: Path | None = None
        created_venv = False
        if command == "rebuild":
            if not manifest.is_file() or not (project / "uv.lock").is_file():
                raise ValueError("Rebuild requires pyproject.toml and uv.lock; run init first.")
            if venv.exists():
                backup_venv = project / f".venv.{MARKER}-backup-{os.getpid()}"
                if backup_venv.exists():
                    shutil.rmtree(backup_venv)
                venv.rename(backup_venv)
        try:
            if not manifest.exists():
                run("init", "--bare", "--no-workspace", "--no-pin-python", "--vcs", "none", "--name", kernel_name(project))
            if not venv.exists():
                created_venv = True
                run("venv", str(venv))
            if command == "init":
                deps = data.get("dependency-groups", {}).get("dev", [])
                if not any(isinstance(dep, str) and re.match(r"(?i)^ipykernel(?:$|[<>=!~;\[ @])", dep) for dep in deps):
                    run("add", "--dev", "ipykernel", "--no-sync")
                if not (project / "uv.lock").is_file():
                    run("lock")
            current_data = tomllib.loads(manifest.read_text()) if manifest.exists() else {}
            if "dev" in current_data.get("dependency-groups", {}):
                run("sync", "--locked", "--group", "dev")
            else:
                run("sync", "--locked")
            subprocess.run([str(venv / "bin/python"), "-I", "-c", "import ipykernel"], env=env, check=True)
            atomic_json(project / f".{MARKER}.json", {"project": str(project)})
        except BaseException:
            if backup_venv is not None and backup_venv.exists():
                if venv.exists():
                    shutil.rmtree(venv)
                backup_venv.rename(venv)
            elif created_venv and venv.exists():
                shutil.rmtree(venv)
            raise
        if backup_venv is not None and backup_venv.exists():
            shutil.rmtree(backup_venv)
        spec_dir.mkdir(exist_ok=True)
        atomic_json(
            target,
            {
                "argv": [sys.executable, "-I", str(Path(__file__).resolve()), "launch", str(project), "-f", "{connection_file}"],
                "display_name": f"Python (uv: {project.name})",
                "language": "python",
                "metadata": {MARKER: {"project": str(project)}},
            },
        )
        print(f"Registered {kernel_name(project)}. Select Python (uv: {project.name}).")


def main() -> int:
    parser = argparse.ArgumentParser(prog="scigethelpers uv", description=__doc__)
    parser.add_argument(
        "command",
        choices=["init", "rebuild", "remove", "launch"],
        metavar="{init,rebuild,remove}",
        help="create, rebuild after a move or Python change, or unregister",
    )
    parser.add_argument("directory", type=Path, help="the uv project directory")
    args, rest = parser.parse_known_args()
    try:
        project = args.directory.expanduser().resolve()
        if args.command == "launch":
            launch(project, rest)
        else:
            if rest:
                parser.error(f"unexpected arguments: {rest}")
            prepare(project, args.command)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"scigethelpers uv: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
