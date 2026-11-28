#!/opt/conda/bin/python3 -I
"""The `scigethelpers` command: one entry point for sciget session helpers.

Generalized from neurodesk/neurodesktop (config/jupyter/neurodesk_cli.py, MIT,
Copyright (c) 2021 NeuroDesk; /opt/scigethelpers-cli/LICENSE) for any sciget
domain image (neurodesktop, microdesktop, and others).

Each helper stays an independent executable under its own name, so its
interpreter and existing callers (kernelspecs) are unchanged. This dispatcher
maps `scigethelpers <command>` onto that executable and provides built-in
read-only commands: `check`, `info`, and `agent preflight`.
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
from contextlib import suppress
import difflib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from collections.abc import Callable, Sequence
from dataclasses import asdict, dataclass
from pathlib import Path

BIN_DIR = Path("/usr/local/bin")
MANIFESTS = Path("/opt/scidesktop/manifest.d")
CVMFS_ROOT = Path("/cvmfs")
CVMFS_CONFIG_DIR = Path("/etc/cvmfs/config.d")
BEFORE_NOTEBOOK_DIR = Path("/usr/local/bin/before-notebook.d")
VIRTUALGL_ENV_HOOK = BEFORE_NOTEBOOK_DIR / "13-virtualgl-env.sh"
SYSTEM_CATALOGS = Path("/etc/sciget/catalogs.json")
LMOD_EXEC = Path("/opt/apps/lmod/lmod/libexec/lmod")
GROUPS = ("Analysis", "Environment", "Agents")

VALID_CVMFS_REPO = re.compile(r"^[A-Za-z0-9._-]+$")
SOFTWARE_RENDERERS = ("llvmpipe", "softpipe", "swrast", "swiftshader")

# Track active child process groups without a Python Lock so SIGTERM/SIGINT
# handlers can never deadlock if a signal interrupts the main thread while
# registering or unregistering a probe. `_TERMINATING` prevents worker threads
# from launching new probes once shutdown has begun.
_CHILD_PGIDS: dict[int, bool] = {}
_TERMINATING = False


def _kill_all_child_pgids() -> None:
    for pgid in list(_CHILD_PGIDS):
        with suppress(OSError):
            os.killpg(pgid, signal.SIGKILL)


def _handle_termination(signum: int, _frame: object) -> None:
    global _TERMINATING
    _TERMINATING = True
    _kill_all_child_pgids()
    os._exit(128 + signum)


def _deadline_from_env(default_seconds: float) -> float:
    raw = os.environ.get("SCIGETHELPERS_DEADLINE_SECONDS", "").strip()
    if raw:
        with suppress(ValueError):
            val = float(raw)
            if val > 0:
                return time.monotonic() + min(val, default_seconds)
    return time.monotonic() + default_seconds


def _remaining(deadline: float | None, cap: float) -> float:
    if deadline is None:
        return cap
    return max(0.0, min(cap, deadline - time.monotonic()))


@dataclass(frozen=True)
class Command:
    words: tuple[str, ...]
    group: str
    summary: str
    target: str | Callable[[Sequence[str]], int]

    @property
    def name(self) -> str:
        return " ".join(self.words)


def usage() -> str:
    width = max(len(command.name) for command in COMMANDS) + 2
    lines = [
        "usage: scigethelpers <command> [<args>]",
        "",
        "Sciget session helper commands.",
    ]
    for group in GROUPS:
        lines += ["", f"{group}:"]
        lines += [f"  {command.name:<{width}} {command.summary}"
                  for command in COMMANDS if command.group == group]
    lines += [
        "",
        "Run 'scigethelpers <command> --help' for the options of a command.",
        "Standalone commands scigethelpers-cite, scigethelpers-kernel and scigethelpers-uv also work.",
    ]
    return "\n".join(lines) + "\n"


def find(words: Sequence[str]) -> tuple[Command | None, list[Command]]:
    """Return the command named by the leading words and the partial matches."""
    for command in COMMANDS:
        if tuple(words[:len(command.words)]) == command.words:
            return command, []
    partial = [command for command in COMMANDS if words and command.words[0] == words[0]]
    return None, partial


def unknown(name: str) -> int:
    names = sorted({command.words[0] for command in COMMANDS})
    message = f"scigethelpers: unknown command '{name}'."
    close = difflib.get_close_matches(name, names, n=1)
    if close:
        message += f" Did you mean '{close[0]}'?"
    print(f"{message}\nRun 'scigethelpers --help' to list commands.", file=sys.stderr)
    return 2


# --- shared subprocess and probe helpers -----------------------------------

@dataclass(frozen=True)
class Result:
    status: str  # PASS, FAIL or SKIP
    detail: str
    repo: str | None = None


def run(argv: Sequence[str], timeout: float, env: dict[str, str] | None = None
        ) -> subprocess.CompletedProcess[str] | None:
    """Run argv; return None, without blocking forever, after timeout."""
    if timeout <= 0 or _TERMINATING:
        return None
    try:
        process = subprocess.Popen(list(argv), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True,
                                   env=env)
    except OSError as error:
        return subprocess.CompletedProcess(list(argv), 127, "", str(error))
    pgid = process.pid
    _CHILD_PGIDS[pgid] = True
    if _TERMINATING:
        with suppress(OSError):
            os.killpg(pgid, signal.SIGKILL)
        _CHILD_PGIDS.pop(pgid, None)
        return None
    try:
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            # A process in uninterruptible CVMFS I/O cannot exit, and a descendant
            # can hold its pipes open, so signal the group, close pipes, and reap
            # briefly before abandoning it.
            with suppress(OSError):
                os.killpg(pgid, signal.SIGKILL)
            for stream in (process.stdout, process.stderr):
                if stream is not None:
                    with suppress(OSError):
                        stream.close()
            with suppress(subprocess.TimeoutExpired):
                process.wait(timeout=1)
            return None
        return subprocess.CompletedProcess(list(argv), process.returncode, stdout, stderr)
    finally:
        _CHILD_PGIDS.pop(pgid, None)


def first_line(text: str) -> str:
    return next((line.strip() for line in text.splitlines() if line.strip()), "no output")


def _valid_cvmfs_repo(name: str) -> bool:
    return bool(name) and name not in {".", ".."} and VALID_CVMFS_REPO.fullmatch(name) is not None


def _dedupe_valid_repos(candidates: Sequence[str]) -> list[str]:
    seen: dict[str, None] = {}
    for candidate in candidates:
        repo = candidate.strip()
        if _valid_cvmfs_repo(repo):
            seen[repo] = None
    return list(seen)


def _repos_from_cvmfs_hooks() -> list[str]:
    """Evaluate read-only *-cvmfs.sh hooks in a subshell when env var is unset."""
    if not BEFORE_NOTEBOOK_DIR.is_dir():
        return []
    hooks = sorted(BEFORE_NOTEBOOK_DIR.glob("*-cvmfs.sh"))
    if not hooks:
        return []
    script = (
        'for f in "$@"; do [ -r "$f" ] && . "$f" >/dev/null 2>&1; done; '
        'printf "%s" "${SCIDESKTOP_CVMFS_REPOSITORIES:-}"'
    )
    result = run(["bash", "-c", script, "cvmfs-hooks", *(str(h) for h in hooks)], 5)
    if result is None or result.returncode != 0:
        return []
    return _dedupe_valid_repos(result.stdout.split(","))


def _repos_from_cvmfs_dir(timeout: float = 5) -> list[str]:
    """List /cvmfs in a bounded child process so a hung FUSE mount never blocks."""
    code = (
        "import os, sys\n"
        "root = sys.argv[1]\n"
        "if os.path.isdir(root):\n"
        "    for name in sorted(os.listdir(root)):\n"
        "        if os.path.isdir(os.path.join(root, name)):\n"
        "            print(name)\n"
    )
    result = run([sys.executable, "-I", "-c", code, str(CVMFS_ROOT)], timeout)
    if result is None or result.returncode != 0:
        return []
    return _dedupe_valid_repos(result.stdout.splitlines())


def configured_cvmfs_repos(*, allow_dir_scan: bool = True) -> list[str]:
    """CVMFS repositories configured for this session, validated and deduplicated."""
    if os.environ.get("SCIDESKTOP_CVMFS_MODE") == "disabled":
        return []
    raw = os.environ.get("SCIDESKTOP_CVMFS_REPOSITORIES", "").strip()
    if raw:
        return _dedupe_valid_repos(raw.split(","))
    repos = _repos_from_cvmfs_hooks()
    if CVMFS_CONFIG_DIR.is_dir():
        for conf in sorted(CVMFS_CONFIG_DIR.glob("*.conf")):
            if conf.name != "default.conf":
                repos.append(conf.stem)
    repos = _dedupe_valid_repos(repos)
    if not repos and allow_dir_scan:
        repos = _repos_from_cvmfs_dir()
    return repos


# A hung FUSE mount blocks the caller forever, so every CVMFS read happens in
# a child process that a timeout can abandon. Require CVMFS-specific evidence
# (CVMFS xattrs user.host/user.fqrn, or a fuse/cvmfs mount on the repo path
# itself) so an ordinary bind mount or /proc directory cannot falsely pass.
CVMFS_PROBE = """
import os, sys
root = sys.argv[1]
entries = os.listdir(root)
modules = os.path.join(root, "neurodesk-modules")
count = len(os.listdir(modules)) if os.path.isdir(modules) else len(entries)
kind = "module categories" if os.path.isdir(modules) else "entries"
host = ""
has_cvmfs_xattr = False
for attr in ("user.host", "user.fqrn"):
    try:
        val = os.getxattr(root, attr).decode().strip()
        has_cvmfs_xattr = True
        if attr == "user.host":
            host = val
    except OSError:
        pass
mounted = has_cvmfs_xattr
if not mounted:
    try:
        real_root = os.path.realpath(root)
        with open("/proc/mounts", "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                parts = line.split()
                if len(parts) >= 3 and parts[1] in (root, real_root):
                    fstype = parts[2].lower()
                    if fstype == "cvmfs" or fstype.startswith("fuse"):
                        mounted = True
                        break
    except OSError:
        pass
print(f"{count}\\t{kind}\\t{1 if mounted else 0}")
print(host)
"""


@dataclass(frozen=True)
class CvmfsProbeResult:
    repo: str
    ok: bool
    count: int = 0
    kind: str = "entries"
    mounted: bool = False
    host: str = ""
    error: str = ""


def probe_cvmfs(repo: str, timeout: float = 60) -> CvmfsProbeResult:
    """Probe one CVMFS repository in a bounded child process."""
    if not _valid_cvmfs_repo(repo):
        return CvmfsProbeResult(repo=repo, ok=False, error=f"invalid repository name {repo!r}")
    repo_path = CVMFS_ROOT / repo
    if timeout <= 0:
        return CvmfsProbeResult(repo=repo, ok=False, error=f"deadline exceeded before probing {repo_path}")
    result = run([sys.executable, "-I", "-c", CVMFS_PROBE, str(repo_path)], timeout)
    if result is None:
        return CvmfsProbeResult(repo=repo, ok=False, error=f"no response from {repo_path} within {timeout:.0f} s")
    if result.returncode != 0:
        return CvmfsProbeResult(repo=repo, ok=False, error=f"{repo_path} is not readable")
    first, _, host = result.stdout.partition("\n")
    parts = first.split("\t")
    if len(parts) < 3:
        return CvmfsProbeResult(repo=repo, ok=False, error=f"unexpected probe output for {repo_path}")
    count = int(parts[0])
    kind = parts[1] or "entries"
    mounted = parts[2] == "1"
    if count == 0:
        return CvmfsProbeResult(repo=repo, ok=False, mounted=mounted, host=host.strip(),
                                error=f"{repo_path} is empty")
    if not mounted:
        return CvmfsProbeResult(repo=repo, ok=False, count=count, kind=kind, mounted=False,
                                host=host.strip(), error=f"{repo_path} is not a CVMFS mount")
    return CvmfsProbeResult(repo=repo, ok=True, count=count, kind=kind, mounted=True, host=host.strip())


def probe_cvmfs_repos(repos: Sequence[str], timeout: float = 60) -> list[CvmfsProbeResult]:
    """Probe all configured repositories concurrently within one shared deadline."""
    if not repos:
        return []
    deadline = time.monotonic() + timeout
    if len(repos) == 1:
        return [probe_cvmfs(repos[0], timeout=max(0.0, deadline - time.monotonic()))]

    def _worker(repo_name: str) -> CvmfsProbeResult:
        # Compute remaining budget when this worker actually starts so queued
        # repos never overshoot the shared deadline.
        rem = deadline - time.monotonic()
        if rem <= 0:
            return CvmfsProbeResult(
                repo=repo_name,
                ok=False,
                error=f"no response from {CVMFS_ROOT / repo_name} within {timeout:.0f} s",
            )
        return probe_cvmfs(repo_name, timeout=rem)

    results: dict[str, CvmfsProbeResult] = {}
    with ThreadPoolExecutor(max_workers=min(len(repos), 8)) as pool:
        future_to_repo = {pool.submit(_worker, repo): repo for repo in repos}
        for future in as_completed(future_to_repo):
            repo = future_to_repo[future]
            try:
                results[repo] = future.result()
            except Exception as error:
                results[repo] = CvmfsProbeResult(repo=repo, ok=False, error=str(error))
    return [results[repo] for repo in repos]


def _cvmfs_results_from_probes(
    mode: str, repos: Sequence[str], probed_list: Sequence[CvmfsProbeResult]
) -> list[Result]:
    if mode == "disabled":
        return [Result("SKIP", "CVMFS is disabled (SCIDESKTOP_CVMFS_MODE=disabled)")]
    if not repos:
        return [Result("SKIP", "no CVMFS repository configured in this image")]
    out: list[Result] = []
    for probed in probed_list:
        if not probed.ok:
            out.append(Result("FAIL", f"{probed.repo}: {probed.error}", repo=probed.repo))
        else:
            server = f" from {probed.host}" if probed.host else ""
            out.append(Result("PASS", f"{probed.repo}: {probed.count} {probed.kind}{server}", repo=probed.repo))
    return out


def check_cvmfs(deadline: float | None = None) -> list[Result]:
    mode = os.environ.get("SCIDESKTOP_CVMFS_MODE") or "external"
    if mode == "disabled":
        return [Result("SKIP", "CVMFS is disabled (SCIDESKTOP_CVMFS_MODE=disabled)")]
    repos = configured_cvmfs_repos()
    if not repos:
        return [Result("SKIP", "no CVMFS repository configured in this image")]
    budget = _remaining(deadline, 60.0)
    return _cvmfs_results_from_probes(mode, repos, probe_cvmfs_repos(repos, timeout=budget))


# --- GPU probe -------------------------------------------------------------

def _nvidia_device_nodes_present() -> bool:
    dev = Path("/dev")
    if not dev.is_dir():
        return False
    if (dev / "nvidiactl").exists():
        return True
    with suppress(OSError):
        return any(p.name.startswith("nvidia") and p.name[6:].isdigit() for p in dev.iterdir())
    return False


def probe_nvidia(timeout: float = 30.0) -> tuple[str, list[str], str]:
    """Return (state, devices, detail) where state is 'ok', 'absent', or 'error'."""
    if shutil.which("nvidia-smi") is None:
        if _nvidia_device_nodes_present():
            return "error", [], "NVIDIA device nodes present in /dev, but nvidia-smi is not installed"
        return "absent", [], ""
    result = run(["nvidia-smi", "-L"], timeout)
    if result is None:
        return "error", [], f"nvidia-smi timed out after {timeout:.0f} s"
    if result.returncode != 0:
        detail = first_line(result.stderr or result.stdout)
        if _nvidia_device_nodes_present():
            return "error", [], f"nvidia-smi failed: {detail}"
        return "absent", [], ""
    devices = [line for line in result.stdout.splitlines() if line.startswith("GPU ")]
    if not devices:
        return "absent", [], ""
    return "ok", devices, ""


def nvidia_devices() -> list[str]:
    state, devices, _ = probe_nvidia()
    return devices if state == "ok" else []


def resolve_vgl_display(timeout: float = 5.0) -> str:
    explicit = os.environ.get("VGL_DISPLAY", "").strip()
    if explicit:
        return explicit
    if VIRTUALGL_ENV_HOOK.is_file() and os.access(VIRTUALGL_ENV_HOOK, os.R_OK):
        result = run(
            ["bash", "-c", '. "$1" >/dev/null 2>&1; printf "%s" "${VGL_DISPLAY:-}"',
             "virtualgl-env", str(VIRTUALGL_ENV_HOOK)],
            timeout,
        )
        if result is not None and result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    return ""


def _x11_display_reachable(display: str, deadline: float | None = None) -> bool:
    """True when the local X11 display socket exists and responds."""
    if not display:
        return False
    if display.startswith(":"):
        num = display[1:].split(".", 1)[0]
        if not num.isdigit():
            return False
        if not Path(f"/tmp/.X11-unix/X{num}").exists():
            return False
    if shutil.which("xrdb") is not None:
        result = run(["xrdb", "-query"], _remaining(deadline, 3.0))
        return result is not None and result.returncode == 0
    return True


def _extract_gl_field(text: str, prefixes: Sequence[str]) -> str:
    for line in text.splitlines():
        stripped = line.strip()
        for prefix in prefixes:
            if stripped.startswith(prefix):
                return stripped[len(prefix):].strip()
    return ""


def _is_software_renderer(vendor: str, renderer: str) -> bool:
    lower_renderer = renderer.lower()
    if any(sw in lower_renderer for sw in SOFTWARE_RENDERERS):
        return True
    if vendor and "nvidia" not in vendor.lower():
        return True
    return False


def _gpu_result_from_probe(
    state: str, devices: Sequence[str], error: str, deadline: float | None = None
) -> list[Result]:
    if state == "error":
        return [Result("FAIL", error)]
    if state == "absent":
        return [Result("SKIP", "no NVIDIA GPU visible in this container")]

    summary = f"{len(devices)} NVIDIA device(s)"
    eglinfo = shutil.which("vgl-eglinfo")
    vglrun = shutil.which("vglrun")
    vgl_display = resolve_vgl_display(_remaining(deadline, 5.0))

    if eglinfo is None and vglrun is None:
        return [Result("PASS", f"{summary} (VirtualGL not installed)")]
    if not vgl_display:
        return [Result("PASS", f"{summary} (compute available; VirtualGL EGL display not resolved)")]

    egl_verified = False
    egl_note = ""
    if eglinfo is not None:
        egl = run([eglinfo, vgl_display, "-B"], _remaining(deadline, 20.0))
        if egl is None:
            egl_note = f"EGL probe timed out on {vgl_display}"
        elif egl.returncode != 0:
            egl_note = f"EGL rendering unavailable on {vgl_display}: {first_line(egl.stderr or egl.stdout)}"
        else:
            vendor = _extract_gl_field(egl.stdout, ("OpenGL vendor string:", "EGL vendor string:"))
            renderer = _extract_gl_field(egl.stdout, ("OpenGL renderer string:",))
            if _is_software_renderer(vendor, renderer) or (not vendor and not renderer):
                egl_note = (
                    f"EGL did not report NVIDIA hardware rendering "
                    f"(vendor={vendor or 'unknown'}, renderer={renderer or 'unknown'})"
                )
            else:
                egl_verified = True
    else:
        egl_note = "vgl-eglinfo not installed"

    # If vgl-eglinfo ran and could not verify NVIDIA EGL (for example a
    # compute-only GPU container without graphics capabilities), keep the check
    # PASS with an explicit compute-only note even after the desktop starts.
    if eglinfo is not None and not egl_verified:
        return [Result("PASS", f"{summary} (compute available; {egl_note})")]

    display = os.environ.get("DISPLAY", "").strip()
    glxinfo = shutil.which("glxinfo")
    if vglrun is not None and glxinfo is not None and _x11_display_reachable(display, deadline):
        glx = run([vglrun, "-d", vgl_display, "-c", "proxy", glxinfo, "-B"], _remaining(deadline, 20.0))
        if glx is None:
            return [Result("FAIL", f"{summary}; desktop OpenGL probe timed out on {display}")]
        if glx.returncode != 0:
            detail = first_line(glx.stderr or glx.stdout)
            return [Result("FAIL", f"{summary}; desktop OpenGL probe failed on {display}: {detail}")]
        vendor = _extract_gl_field(glx.stdout, ("OpenGL vendor string:",))
        renderer = _extract_gl_field(glx.stdout, ("OpenGL renderer string:",))
        if _is_software_renderer(vendor, renderer):
            return [Result("FAIL", f"{summary}; desktop OpenGL is software/non-NVIDIA "
                                   f"(vendor={vendor or 'unknown'}, renderer={renderer or 'unknown'})")]
        egl_part = f"EGL ({vgl_display}) and " if egl_verified else ""
        return [Result("PASS", f"{summary}; {egl_part}desktop OpenGL ({renderer or vendor}) work")]

    if egl_verified:
        return [Result("PASS", f"{summary}; NVIDIA EGL ({vgl_display}) works (desktop display not running; GLX skipped)")]
    return [Result("PASS", f"{summary} (compute available; {egl_note})")]


def check_gpu(deadline: float | None = None) -> list[Result]:
    state, devices, error = probe_nvidia(_remaining(deadline, 25.0))
    return _gpu_result_from_probe(state, devices, error, deadline=deadline)


# --- Slurm and T3 checks ---------------------------------------------------

def check_slurm(deadline: float | None = None) -> list[Result]:
    if shutil.which("sinfo") is None:
        return [Result("SKIP", "Slurm is not installed")]
    result = run(["sinfo", "--noheader", "--format=%P %t"], _remaining(deadline, 15.0))
    if result is None:
        return [Result("FAIL", "sinfo timed out; the controller may still be starting")]
    if result.returncode != 0:
        return [Result("FAIL", first_line(result.stderr))]
    partitions = [line.split()[0] for line in result.stdout.splitlines() if line.split()]
    return [Result("PASS", f"partitions: {', '.join(dict.fromkeys(partitions)) or 'none'}")]


def _t3_base_dir() -> Path:
    return Path(os.environ.get("T3CODE_HOME") or Path.home() / ".t3").expanduser()


def _proc_matches_t3_serve(pid: int, target_base: Path) -> bool:
    try:
        argv = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    except OSError:
        return False
    if len(argv) < 4 or argv[1] != b"serve":
        return False
    exe_name = os.path.basename(argv[0].decode("utf-8", "replace"))
    if exe_name != "t3":
        return False
    target = str(target_base).encode()
    return any(argv[i] == b"--base-dir" and argv[i + 1] == target for i in range(2, len(argv) - 1))


def check_t3(_deadline: float | None = None) -> list[Result]:
    """Strictly read-only T3 Code / T3 Connect check; never creates ~/.t3 or starts T3."""
    if not (MANIFESTS / "t3-code.json").is_file():
        return [Result("SKIP", "T3 Code is not installed")]
    base = _t3_base_dir()
    if not base.is_dir():
        return [Result("SKIP", "T3 Code has not been started in this session; open scigent.ai or /t3-connect/")]
    if (base / "connect-revoke-pending").exists():
        return [Result("FAIL", "previous T3 Connect disconnect left a pending relay revocation; open /t3-connect/ to retry")]
    runtime_file = base / "userdata" / "server-runtime.json"
    running_pid: int | None = None
    if runtime_file.is_file():
        with suppress(OSError, ValueError):
            data = json.loads(runtime_file.read_text(encoding="utf-8"))
            pid = data.get("pid") if isinstance(data, dict) else None
            if isinstance(pid, int) and pid > 0 and _proc_matches_t3_serve(pid, base):
                running_pid = pid
    connect_installed = (MANIFESTS / "t3-connect.json").is_file()
    relay_note = "; check /t3-connect/ for live relay status" if connect_installed else ""
    if running_pid is not None:
        return [Result("PASS", f"T3 Code server running (pid {running_pid}){relay_note}")]
    return [Result("PASS", f"T3 Code data present at {base}, server idle (starts on demand){relay_note}")]


CHECKS: dict[str, Callable[[float | None], list[Result]]] = {
    "cvmfs": check_cvmfs,
    "gpu": check_gpu,
    "slurm": check_slurm,
    "t3": check_t3,
}

CHECK_HELP = f"""usage: scigethelpers check [--json] [{' | '.join(CHECKS)}] ...

Run read-only health checks; with no names, run all of them.
Each check prints PASS, FAIL or SKIP. The exit status is 1 when a check fails.

  cvmfs  configured CVMFS repositories are mounted and readable
  gpu    an NVIDIA GPU is visible and VirtualGL EGL / desktop OpenGL renders
  slurm  the Slurm controller answers and lists partitions
  t3     T3 Code local state and pending T3 Connect revocations (read-only)
"""


def run_checks(names: Sequence[str], deadline: float | None = None) -> tuple[list[dict[str, object]], bool]:
    """Run selected checks concurrently within one shared deadline, preserving order."""
    if deadline is None:
        deadline = _deadline_from_env(65.0)
    by_name: dict[str, list[Result]] = {}
    if len(names) <= 1:
        for name in names:
            by_name[name] = CHECKS[name](deadline)
    else:
        with ThreadPoolExecutor(max_workers=len(names)) as pool:
            future_to_name = {pool.submit(CHECKS[name], deadline): name for name in names}
            for future in as_completed(future_to_name):
                name = future_to_name[future]
                try:
                    by_name[name] = future.result()
                except Exception as error:
                    by_name[name] = [Result("FAIL", str(error))]
    entries: list[dict[str, object]] = []
    failed = False
    for name in names:
        for result in by_name.get(name, []):
            failed |= result.status == "FAIL"
            entry: dict[str, object] = {
                "name": name,
                "status": result.status,
                "detail": result.detail,
            }
            if result.repo is not None:
                entry["repo"] = result.repo
            entries.append(entry)
    return entries, failed


def command_check(args: Sequence[str]) -> int:
    if any(arg in {"-h", "--help"} for arg in args):
        print(CHECK_HELP, end="")
        return 0
    as_json = False
    selected: list[str] = []
    for arg in args:
        if arg == "--json":
            as_json = True
        elif arg.startswith("-"):
            print(f"scigethelpers check: unknown option '{arg}'.", file=sys.stderr)
            return 2
        else:
            selected.append(arg)
    unknown_names = [name for name in selected if name not in CHECKS]
    if unknown_names:
        print(f"scigethelpers check: unknown check '{unknown_names[0]}'. "
              f"Choose from: {', '.join(CHECKS)}.", file=sys.stderr)
        return 2
    names = list(dict.fromkeys(selected)) or list(CHECKS)
    deadline = _deadline_from_env(65.0)
    entries, failed = run_checks(names, deadline=deadline)
    if as_json:
        print(json.dumps({"ok": not failed, "checks": entries}, indent=2))
        return 1 if failed else 0
    for item in entries:
        print(f"[{item['status']}] {item['name']:<6} {item['detail']}", flush=True)
    return 1 if failed else 0


# --- info ------------------------------------------------------------------

def read_text(path: str) -> str:
    try:
        return Path(path).read_text().strip()
    except OSError:
        return ""


def read_resource_limits() -> dict[str, str]:
    """Read CPU_LIMIT, CPU_QUOTA and MEM_LIMIT from env or startup's helper."""
    limits = {k: os.environ[k].strip() for k in ("CPU_LIMIT", "MEM_LIMIT") if os.environ.get(k, "").strip()}
    helper = Path("/opt/scidesktop/resource-limits")
    if len(limits) < 2 and os.access(helper, os.X_OK):
        result = run([str(helper)], 5)
        if result is not None and result.returncode == 0:
            for line in result.stdout.splitlines():
                key, sep, val = line.partition("=")
                if sep and key in ("CPU_LIMIT", "CPU_QUOTA", "MEM_LIMIT") and val.strip():
                    limits.setdefault(key, val.strip())
    return limits


def memory_limit_bytes(limits: dict[str, str] | None = None) -> int:
    total_kib = next((int(line.split()[1]) for line in read_text("/proc/meminfo").splitlines()
                      if line.startswith("MemTotal:")), 0)
    limit_bytes = total_kib * 1024
    resolved = read_resource_limits() if limits is None else limits
    raw = resolved.get("MEM_LIMIT", "")
    if raw.isdigit() and int(raw) > 0:
        limit_bytes = min(limit_bytes, int(raw)) if limit_bytes else int(raw)
    return limit_bytes


def memory_limit(limits: dict[str, str] | None = None) -> str:
    limit_bytes = memory_limit_bytes(limits)
    return f"{limit_bytes / 2**30:.1f} GiB" if limit_bytes else "unknown"


def cpu_limit(limits: dict[str, str] | None = None) -> str:
    available = len(os.sched_getaffinity(0))
    resolved = read_resource_limits() if limits is None else limits
    raw = os.environ.get("CPU_LIMIT", "").strip() or resolved.get("CPU_QUOTA", "") or resolved.get("CPU_LIMIT", "")
    try:
        if raw and float(raw) > 0:
            return f"{min(float(available), float(raw)):g}"
    except ValueError:
        pass
    return str(available)


def image_component_list() -> list[str]:
    return sorted(path.stem for path in MANIFESTS.glob("*.json"))


def image_components() -> str:
    """The image's components, as its manifest names them."""
    return ", ".join(image_component_list()) or "unknown"


def collect_info(
    *,
    run_probes: bool = True,
    deadline: float | None = None,
) -> dict[str, object]:
    home = Path.home()
    usage_ = shutil.disk_usage(home)
    limits = read_resource_limits()
    mem_bytes = memory_limit_bytes(limits)
    cvmfs_mode = os.environ.get("SCIDESKTOP_CVMFS_MODE") or "external"
    # Never touch /cvmfs directory fallback when --no-probes or CVMFS is disabled.
    repos = configured_cvmfs_repos(allow_dir_scan=run_probes)

    if run_probes:
        probe_deadline = deadline if deadline is not None else _deadline_from_env(25.0)
        # Run GPU and CVMFS probes concurrently within the shared budget.
        with ThreadPoolExecutor(max_workers=2) as pool:
            gpu_fut = pool.submit(probe_nvidia, _remaining(probe_deadline, 20.0))
            cvmfs_fut = (
                pool.submit(probe_cvmfs_repos, repos, _remaining(probe_deadline, 20.0))
                if (cvmfs_mode != "disabled" and repos)
                else None
            )
            gpu_state, devices, gpu_err = gpu_fut.result()
            cvmfs_probed = cvmfs_fut.result() if cvmfs_fut is not None else []
        gpu_info: dict[str, object] = {
            "probed": True,
            "state": gpu_state,
            "devices": devices,
            "error": gpu_err or None,
        }
        cvmfs_repos_info: list[dict[str, object]] = [asdict(r) for r in cvmfs_probed]
    else:
        gpu_info = {"probed": False, "state": "not_probed", "devices": [], "error": None}
        cvmfs_repos_info = [{"repo": r, "probed": False} for r in repos]

    return {
        "components": image_component_list(),
        "user": os.environ.get("USER") or str(os.getuid()),
        "home": str(home),
        "cpus": cpu_limit(limits),
        "memory": f"{mem_bytes / 2**30:.1f} GiB" if mem_bytes else "unknown",
        "memory_gib": round(mem_bytes / 2**30, 1) if mem_bytes else None,
        "home_disk": {
            "free_gib": round(usage_.free / 2**30, 1),
            "total_gib": round(usage_.total / 2**30, 1),
        },
        "gpu": gpu_info,
        "cvmfs": {
            "mode": cvmfs_mode,
            "configured_repos": repos,
            "probed": run_probes,
            "repos": cvmfs_repos_info,
        },
    }


def _format_cvmfs_info_row(cvmfs_info: dict[str, object]) -> str:
    if cvmfs_info["mode"] == "disabled":
        return "disabled"
    configured = cvmfs_info["configured_repos"]
    assert isinstance(configured, list)
    if not configured:
        return "not configured"
    if not cvmfs_info["probed"]:
        return ", ".join(str(r) for r in configured) + " (not probed)"
    parts: list[str] = []
    repos = cvmfs_info["repos"]
    assert isinstance(repos, list)
    for item in repos:
        assert isinstance(item, dict)
        repo = item["repo"]
        if item.get("ok"):
            parts.append(f"{repo} (mounted, server {item.get('host') or 'unknown'})")
        else:
            parts.append(f"{repo} ({item.get('error') or 'unavailable'})")
    return "; ".join(parts)


INFO_HELP = """usage: scigethelpers info [--json] [--no-probes]

Show the image's components, resources, GPU and CVMFS state.

  --json       print machine-readable JSON
  --no-probes  skip live GPU and CVMFS probes (local facts only)
"""


def command_info(args: Sequence[str]) -> int:
    as_json = False
    run_probes = True
    for arg in args:
        if arg in {"-h", "--help"}:
            print(INFO_HELP, end="")
            return 0
        if arg == "--json":
            as_json = True
        elif arg == "--no-probes":
            run_probes = False
        else:
            print(INFO_HELP, end="", file=sys.stderr)
            return 2

    info = collect_info(run_probes=run_probes)
    if as_json:
        print(json.dumps(info, indent=2))
        return 0

    gpu = info["gpu"]
    assert isinstance(gpu, dict)
    if not gpu["probed"]:
        gpu_text = "not probed"
    elif gpu["state"] == "ok":
        gpu_text = "; ".join(gpu["devices"])
    elif gpu["state"] == "error":
        gpu_text = f"error ({gpu['error']})"
    else:
        gpu_text = "none visible"

    disk = info["home_disk"]
    assert isinstance(disk, dict)
    cvmfs = info["cvmfs"]
    assert isinstance(cvmfs, dict)

    rows = [
        ("Image", ", ".join(info["components"]) or "unknown"),
        ("User", f"{info['user']} (home {info['home']})"),
        ("CPUs", str(info["cpus"])),
        ("Memory", str(info["memory"])),
        ("Home", f"{disk['free_gib']:.1f} GiB free of {disk['total_gib']:.1f} GiB"),
        ("GPU", gpu_text),
        ("CVMFS", _format_cvmfs_info_row(cvmfs)),
    ]
    width = max(len(label) for label, _ in rows) + 1
    for label, value in rows:
        print(f"{label + ':':<{width}} {value}")
    return 0


# --- agent preflight -------------------------------------------------------

PREFLIGHT_HELP = """usage: scigethelpers agent preflight [--json] [--cwd DIR]

Show installed agent guidance, Lmod, configured Slurm node capacity, GPU,
CVMFS and offline sciget catalog configuration before an analysis.

  --json       print machine-readable JSON
  --cwd DIR    workspace directory to inspect for project AGENTS.md / CLAUDE.md
"""


def _inspect_guidance_path(path: Path) -> dict[str, object]:
    entry: dict[str, object] = {"path": str(path)}
    if path.is_symlink():
        try:
            raw_target = os.readlink(path)
        except OSError as error:
            entry["status"] = "unreadable"
            entry["error"] = str(error)
            return entry
        entry["link_target"] = raw_target
        if not path.exists():
            entry["status"] = "broken_symlink"
            return entry
        try:
            resolved = str(path.resolve(strict=True))
        except OSError:
            resolved = raw_target
        entry["resolved"] = resolved
        entry["status"] = "symlink" if os.access(path, os.R_OK) else "unreadable"
        return entry
    if not path.exists():
        entry["status"] = "missing"
        return entry
    entry["status"] = "file" if os.access(path, os.R_OK) else "unreadable"
    return entry


def _probe_lmod(deadline: float | None = None) -> dict[str, object]:
    lmod_cmd = os.environ.get("LMOD_CMD", "").strip()
    if lmod_cmd and os.access(lmod_cmd, os.X_OK):
        cmd = [lmod_cmd, "bash", "--version"]
    elif LMOD_EXEC.is_file() and os.access(LMOD_EXEC, os.X_OK):
        cmd = [str(LMOD_EXEC), "bash", "--version"]
    else:
        return {"available": False, "version": None, "modulepath": []}
    result = run(cmd, _remaining(deadline, 10.0))
    combined = ((result.stdout or "") + "\n" + (result.stderr or "")).strip() if result else ""
    version_line = next((line.strip() for line in combined.splitlines() if "Version" in line), first_line(combined))
    modulepath = [p for p in os.environ.get("MODULEPATH", "").split(":") if p]
    return {
        "available": result is not None and result.returncode == 0,
        "version": version_line if combined else None,
        "modulepath": modulepath,
    }


def _probe_slurm_capacity(deadline: float | None = None) -> dict[str, object]:
    if shutil.which("sinfo") is None:
        return {"installed": False, "available": False, "partitions": [], "error": None}
    result = run(["sinfo", "--noheader", "-o", "%P|%c|%m|%l|%t"], _remaining(deadline, 15.0))
    if result is None:
        return {"installed": True, "available": False, "partitions": [], "error": "sinfo timed out"}
    if result.returncode != 0:
        return {"installed": True, "available": False, "partitions": [], "error": first_line(result.stderr)}
    partitions: list[dict[str, str]] = []
    for line in result.stdout.splitlines():
        fields = [f.strip() for f in line.split("|")]
        if len(fields) == 5 and fields[0]:
            partitions.append({
                "partition": fields[0],
                "cpus_per_node": fields[1],
                "memory_mib_per_node": fields[2],
                "time_limit": fields[3],
                "node_state": fields[4],
            })
    return {"installed": True, "available": True, "partitions": partitions, "error": None}


def _configured_sciget_catalogs() -> list[dict[str, object]]:
    """Read active sciget catalog definitions offline (system + user layer)."""
    config_base = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    by_name: dict[str, dict[str, object]] = {}
    for path in (SYSTEM_CATALOGS, config_base / "sciget/catalogs.json"):
        try:
            entries = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            name = entry.get("name")
            if not isinstance(name, str) or not name:
                continue
            prev = by_name.get(name, {"name": name, "use": True, "domain": None})
            use = bool(entry["use"]) if "use" in entry else bool(prev["use"])
            domain = entry.get("domain") if isinstance(entry.get("domain"), str) else prev["domain"]
            by_name[name] = {"name": name, "use": use, "domain": domain}
    return [v for v in by_name.values() if v["use"]]


def command_agent_preflight(args: Sequence[str]) -> int:
    as_json = False
    cwd_arg: str | None = None
    idx = 0
    while idx < len(args):
        arg = args[idx]
        if arg in {"-h", "--help"}:
            print(PREFLIGHT_HELP, end="")
            return 0
        if arg == "--json":
            as_json = True
            idx += 1
        elif arg == "--cwd":
            if idx + 1 >= len(args):
                print("scigethelpers agent preflight: --cwd requires a directory", file=sys.stderr)
                return 2
            cwd_arg = args[idx + 1]
            idx += 2
        else:
            print(PREFLIGHT_HELP, end="", file=sys.stderr)
            return 2

    deadline = _deadline_from_env(35.0)
    home = Path.home()
    workspace = Path(cwd_arg).expanduser().resolve() if cwd_arg else Path.cwd()
    user_guidance = [
        {"agent": "codex", **_inspect_guidance_path(home / ".codex" / "AGENTS.md")},
        {"agent": "claude", **_inspect_guidance_path(home / ".claude" / "CLAUDE.md")},
        {"agent": "opencode", **_inspect_guidance_path(home / ".config" / "opencode" / "AGENTS.md")},
    ]
    workspace_guidance = [
        _inspect_guidance_path(workspace / "AGENTS.md"),
        _inspect_guidance_path(workspace / "CLAUDE.md"),
    ]
    catalogs = _configured_sciget_catalogs()

    # Probe Lmod, Slurm, GPU, and CVMFS once (concurrently), reusing results
    # across both `info` and `checks` so nothing is probed twice.
    with ThreadPoolExecutor(max_workers=3) as pool:
        lmod_fut = pool.submit(_probe_lmod, deadline)
        slurm_fut = pool.submit(_probe_slurm_capacity, deadline)
        info_fut = pool.submit(collect_info, run_probes=True, deadline=deadline)
        lmod_info = lmod_fut.result()
        slurm_info = slurm_fut.result()
        info = info_fut.result()

    cvmfs_info = info["cvmfs"]
    assert isinstance(cvmfs_info, dict)
    probed_cvmfs = [
        CvmfsProbeResult(**item)
        for item in cvmfs_info["repos"]
        if isinstance(item, dict) and "ok" in item
    ]
    cvmfs_results = _cvmfs_results_from_probes(
        str(cvmfs_info["mode"]), cvmfs_info["configured_repos"], probed_cvmfs
    )

    gpu_info = info["gpu"]
    assert isinstance(gpu_info, dict)
    gpu_results = _gpu_result_from_probe(
        str(gpu_info["state"]),
        gpu_info["devices"],
        str(gpu_info.get("error") or ""),
        deadline=deadline,
    )

    if not slurm_info["installed"]:
        slurm_results = [Result("SKIP", "Slurm is not installed")]
    elif not slurm_info["available"]:
        slurm_results = [Result("FAIL", str(slurm_info.get("error") or "sinfo failed"))]
    else:
        part_names = list(dict.fromkeys(p["partition"] for p in slurm_info["partitions"]))
        slurm_results = [Result("PASS", f"partitions: {', '.join(part_names) or 'none'}")]

    checks: list[dict[str, object]] = []
    checks_failed = False
    for check_name, results in (("cvmfs", cvmfs_results), ("gpu", gpu_results), ("slurm", slurm_results)):
        for res in results:
            checks_failed |= res.status == "FAIL"
            entry: dict[str, object] = {"name": check_name, "status": res.status, "detail": res.detail}
            if res.repo is not None:
                entry["repo"] = res.repo
            checks.append(entry)

    payload = {
        "workspace": str(workspace),
        "user_guidance": user_guidance,
        "workspace_guidance": workspace_guidance,
        "lmod": lmod_info,
        "slurm_capacity": slurm_info,
        "sciget_catalogs": catalogs,
        "info": info,
        "checks": checks,
        "checks_ok": not checks_failed,
    }

    if as_json:
        print(json.dumps(payload, indent=2))
        return 0

    print("Agent guidance (user defaults):")
    for item in user_guidance:
        status = item["status"]
        extra = ""
        if status == "symlink":
            extra = f" -> {item.get('resolved', item.get('link_target', ''))}"
        elif status == "broken_symlink":
            extra = f" -> {item.get('link_target', '')} (broken)"
        print(f"  {item['agent']:<9} {item['path']} [{status}{extra}]")

    print(f"\nWorkspace guidance ({workspace}):")
    for item in workspace_guidance:
        print(f"  {Path(str(item['path'])).name:<10} [{item['status']}]")

    print("\nLmod:")
    if lmod_info["available"]:
        print(f"  {lmod_info['version'] or 'available'}")
    else:
        print("  unavailable")
    mp = lmod_info["modulepath"]
    assert isinstance(mp, list)
    print(f"  MODULEPATH: {len(mp)} director{'y' if len(mp) == 1 else 'ies'}")

    print("\nSlurm configured node capacity (per-node configured limits, not free resources; memory in MiB):")
    if not slurm_info["installed"]:
        print("  Slurm is not installed")
    elif not slurm_info["available"]:
        print(f"  unavailable ({slurm_info['error'] or 'unknown error'})")
    elif not slurm_info["partitions"]:
        print("  no partitions reported")
    else:
        print(f"  {'PARTITION':<16} {'CPUS/NODE':<10} {'MEM(MiB)':<10} {'TIMELIMIT':<12} STATE")
        for p in slurm_info["partitions"]:
            print(f"  {p['partition']:<16} {p['cpus_per_node']:<10} {p['memory_mib_per_node']:<10} "
                  f"{p['time_limit']:<12} {p['node_state']}")

    print("\nActive sciget catalogs (offline config):")
    if catalogs:
        for cat in catalogs:
            dom = f" (domain: {cat['domain']})" if cat.get("domain") else ""
            print(f"  {cat['name']}{dom}")
    else:
        print("  none configured")

    print("\nSession checks:")
    for item in checks:
        print(f"  [{item['status']}] {item['name']:<6} {item['detail']}")

    return 0


# --- dispatch ----------------------------------------------------------------

COMMANDS = (
    Command(("cite",), "Analysis", "Write CITATIONS.md for the container tools you loaded", "scigethelpers-cite"),
    Command(("kernel",), "Analysis", "Use a tool container's Python as a notebook kernel", "scigethelpers-kernel"),
    Command(("uv",), "Analysis", "Manage project-local uv notebook kernels", "scigethelpers-uv"),
    Command(("check",), "Environment", "Check CVMFS, GPU, Slurm and T3", command_check),
    Command(("info",), "Environment", "Show the image's components, resources, GPU and CVMFS", command_info),
    Command(("agent", "preflight"), "Agents", "Show agent guidance, Lmod, Slurm capacity, GPU and CVMFS",
            command_agent_preflight),
)


def main(argv: Sequence[str] | None = None,
         execv: Callable[[str, list[str]], object] = os.execv) -> int:
    signal.signal(signal.SIGTERM, _handle_termination)
    signal.signal(signal.SIGINT, _handle_termination)
    args = list(sys.argv[1:] if argv is None else argv)
    if not args or args[0] in {"-h", "--help"}:
        print(usage(), end="")
        return 0
    if args[0] == "--version":
        print(f"scigethelpers {read_text(str(MANIFESTS / 'scigethelpers-cli.json')) or 'unknown'}".replace('"', ""))
        return 0
    if args[0] == "help":
        if len(args) == 1:
            print(usage(), end="")
            return 0
        args = [*args[1:], "--help"]

    command, partial = find(args)
    if command is None:
        if partial:
            names = ", ".join(f"'scigethelpers {match.name}'" for match in partial)
            print(f"scigethelpers {args[0]}: choose a command: {names}.", file=sys.stderr)
            return 2
        return unknown(args[0])
    rest = args[len(command.words):]
    if not isinstance(command.target, str):
        return command.target(rest)
    target = BIN_DIR / command.target
    if not os.access(target, os.X_OK):
        print(f"scigethelpers {command.name}: {target} is not installed in this image.", file=sys.stderr)
        return 1
    execv(str(target), [str(target), *rest])
    return 0


if __name__ == "__main__":
    sys.exit(main())
