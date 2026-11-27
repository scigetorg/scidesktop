#!/opt/conda/bin/python3 -I
"""Manage opt-in project-local uv notebook kernels.

Generalized from neurodesk/neurodesktop (config/jupyter/uv_kernel_prototype.py,
MIT, Copyright (c) 2021 NeuroDesk; /opt/scigethelpers-cli/LICENSE) for all
scidesktop images.
"""

from __future__ import annotations

import argparse
from contextlib import suppress
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
KERNEL_WRAPPER = "/opt/scigethelpers-cli/lib/kernel_wrapper.sh"
MODULEPATH_SCRIPT = "/etc/profile.d/z01_lmod_modulepath.sh"


def clean_environment() -> dict[str, str]:
    return {
        key: value
        for key, value in os.environ.items()
        if key not in {"PYTHONPATH", "PYTHONHOME", "VIRTUAL_ENV"}
        and not key.startswith("CONDA_")
    }


def refresh_modulepath(env: dict[str, str]) -> None:
    """Refresh MODULEPATH from z01_lmod_modulepath.sh if kernel_wrapper.sh did not run.

    Existing kernelspecs written before kernel_wrapper.sh was added to argv
    invoke this module's `launch` directly; refreshing here ensures they also
    pick up module directories added after Jupyter started.
    """
    if env.get("_SCIGETHELPERS_MODULEPATH_REFRESHED") == "1":
        return
    if not (os.path.isfile(MODULEPATH_SCRIPT) and os.access(MODULEPATH_SCRIPT, os.R_OK)):
        return
    script = (
        'source "$1" >/dev/null 2>&1; '
        'printf "%s\\0%s" "${MODULEPATH:-}" "${LMOD_AVAIL_EXTENSIONS:-}"'
    )
    with suppress(OSError, subprocess.SubprocessError):
        result = subprocess.run(
            ["bash", "-c", script, "scigethelpers-uv-modulepath", MODULEPATH_SCRIPT],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=10,
            env=env,
        )
        if result.returncode == 0 and "\0" in result.stdout:
            modulepath, avail_ext = result.stdout.split("\0", 1)
            if modulepath:
                env["MODULEPATH"] = modulepath
            if avail_ext:
                env["LMOD_AVAIL_EXTENSIONS"] = avail_ext
            env["_SCIGETHELPERS_MODULEPATH_REFRESHED"] = "1"


def kernel_name(project: Path) -> str:
    slug = re.sub(r"[^a-z0-9_-]+", "-", project.name.lower()).strip("-") or "project"
    digest = hashlib.sha256(os.fsencode(project)).hexdigest()[:12]
    return f"scigethelpers-uv-{slug[:40]}-{digest}"


def atomic_bytes(path: Path, payload: bytes) -> None:
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".uv-kernel-")
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def atomic_json(path: Path, data: dict) -> None:
    atomic_bytes(path, (json.dumps(data, indent=2) + "\n").encode("utf-8"))


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
    refresh_modulepath(env)
    # Never leak the internal refresh guard into kernel processes.
    env.pop("_SCIGETHELPERS_MODULEPATH_REFRESHED", None)
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


def kernels_dir() -> Path:
    from jupyter_core.paths import jupyter_data_dir

    return Path(jupyter_data_dir()) / "kernels"


def owned_uv_specs() -> list[dict[str, object]]:
    root = kernels_dir()
    if not root.is_dir():
        return []
    found: list[dict[str, object]] = []
    for spec_dir in sorted(root.iterdir()):
        if not spec_dir.is_dir() or spec_dir.is_symlink():
            continue
        target = spec_dir / "kernel.json"
        try:
            spec = json.loads(target.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(spec, dict):
            continue
        meta = spec.get("metadata")
        info = meta.get(MARKER) if isinstance(meta, dict) else None
        if not isinstance(info, dict) or not isinstance(info.get("project"), str):
            continue
        project_str = info["project"]
        project_path = Path(project_str)
        available = False
        with suppress(OSError, ValueError):
            available = (
                project_path.is_dir()
                and (project_path / ".venv/bin/python").is_file()
                and read_marker(project_path).get("project") == project_str
            )
        found.append({
            "name": spec_dir.name,
            "display_name": str(spec.get("display_name", spec_dir.name)),
            "project": project_str,
            "available": available,
        })
    return found


def command_list(as_json: bool) -> int:
    specs = owned_uv_specs()
    if as_json:
        print(json.dumps({"kernels": specs}, indent=2))
        return 0
    if not specs:
        print("No uv kernels registered. Create one with: scigethelpers uv init <dir>")
        return 0
    for item in specs:
        state = "" if item["available"] else "  [environment missing or moved]"
        print(f"{item['name']}\t{item['project']}{state}")
    return 0


def prepare(project: Path, command: str, wrapper: Path) -> None:
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
    root = kernels_dir()
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
        if not wrapper.is_file() or not os.access(wrapper, os.X_OK):
            raise ValueError(f"Kernel wrapper unavailable: {wrapper}")
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
        marker_path = project / f".{MARKER}.json"
        old_marker_bytes = marker_path.read_bytes() if marker_path.is_file() else None
        old_target_bytes = target.read_bytes() if target.is_file() else None
        spec_dir_existed = spec_dir.exists()
        target_replaced = False
        marker_replaced = False
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
            spec_dir.mkdir(exist_ok=True)
            atomic_json(
                target,
                {
                    "argv": [
                        str(wrapper),
                        sys.executable,
                        "-I",
                        str(Path(__file__).resolve()),
                        "launch",
                        str(project),
                        "-f",
                        "{connection_file}",
                    ],
                    "display_name": f"Python (uv: {project.name})",
                    "language": "python",
                    "metadata": {MARKER: {"project": str(project)}},
                },
            )
            target_replaced = True
            atomic_json(marker_path, {"project": str(project)})
            marker_replaced = True
        except BaseException:
            if backup_venv is not None and backup_venv.exists():
                if venv.exists():
                    shutil.rmtree(venv)
                backup_venv.rename(venv)
            elif created_venv and venv.exists():
                shutil.rmtree(venv)
            if marker_replaced:
                if old_marker_bytes is not None:
                    try:
                        atomic_bytes(marker_path, old_marker_bytes)
                    except OSError:
                        pass
                else:
                    marker_path.unlink(missing_ok=True)
            if target_replaced:
                if old_target_bytes is not None:
                    try:
                        atomic_bytes(target, old_target_bytes)
                    except OSError:
                        pass
                else:
                    target.unlink(missing_ok=True)
            if not spec_dir_existed and spec_dir.exists():
                try:
                    spec_dir.rmdir()
                except OSError:
                    pass
            raise
        if backup_venv is not None and backup_venv.exists():
            shutil.rmtree(backup_venv)
        print(f"Registered {kernel_name(project)}. Select Python (uv: {project.name}).")


def main(argv: list[str] | None = None) -> int:
    raw_argv = list(sys.argv[1:] if argv is None else argv)
    # `launch` is the internal kernelspec entry point and forwards arbitrary
    # ipykernel flags (e.g. `-f {connection_file}`) unchanged.
    if raw_argv and raw_argv[0] == "launch":
        if len(raw_argv) < 2:
            print("scigethelpers uv: launch requires a project directory", file=sys.stderr)
            return 2
        try:
            project = Path(raw_argv[1]).expanduser().resolve()
            launch(project, raw_argv[2:])
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            print(f"scigethelpers uv: {error}", file=sys.stderr)
            return 1
        return 0

    parser = argparse.ArgumentParser(prog="scigethelpers uv", description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True, metavar="{init,rebuild,remove,list}")

    for name, help_text in (
        ("init", "create a project-local uv environment and register its Jupyter kernel"),
        ("rebuild", "rebuild an existing uv environment after a move or Python change"),
        ("remove", "unregister the uv Jupyter kernel (keeps project files and .venv)"),
    ):
        sub = subparsers.add_parser(name, help=help_text)
        sub.add_argument("directory", type=Path, help="the uv project directory")
        sub.add_argument(
            "--kernel-wrapper",
            type=Path,
            default=Path(KERNEL_WRAPPER),
            help=argparse.SUPPRESS,
        )

    listing = subparsers.add_parser("list", help="list registered uv kernels")
    listing.add_argument("--json", action="store_true", help="print machine-readable JSON")

    args = parser.parse_args(raw_argv)
    try:
        if args.command == "list":
            return command_list(args.json)
        project = args.directory.expanduser().resolve()
        prepare(project, args.command, args.kernel_wrapper.resolve())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"scigethelpers uv: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
