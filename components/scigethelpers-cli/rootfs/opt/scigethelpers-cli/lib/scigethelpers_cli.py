#!/opt/conda/bin/python3 -I
"""The `scigethelpers` command: one entry point for sciget session helpers.

Generalized from neurodesk/neurodesktop (config/jupyter/neurodesk_cli.py, MIT,
Copyright (c) 2021 NeuroDesk; /opt/scigethelpers-cli/LICENSE) for any sciget
domain image (neurodesktop, microdesktop, and others).

Each helper stays an independent executable under its own name, so its
interpreter and existing callers (kernelspecs) are unchanged. This dispatcher
maps `scigethelpers <command>` onto that executable and adds two read-only
commands of its own: `check` and `info`.
"""

from __future__ import annotations

from contextlib import suppress
import difflib
import os
import shutil
import subprocess
import sys
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path

BIN_DIR = Path("/usr/local/bin")
MANIFESTS = Path("/opt/scidesktop/manifest.d")
CVMFS_ROOT = Path("/cvmfs")
CVMFS_CONFIG_DIR = Path("/etc/cvmfs/config.d")
GROUPS = ("Analysis", "Environment")


@dataclass(frozen=True)
class Command:
    words: tuple[str, ...]
    group: str
    summary: str
    # Executable under BIN_DIR that implements the command; None for a
    # command the dispatcher runs itself.
    executable: str | None = None

    @property
    def name(self) -> str:
        return " ".join(self.words)


COMMANDS = (
    Command(("cite",), "Analysis", "Write CITATIONS.md for the container tools you loaded", "scigethelpers-cite"),
    Command(("kernel",), "Analysis", "Use a tool container's Python as a notebook kernel", "scigethelpers-kernel"),
    Command(("check",), "Environment", "Check CVMFS, GPU and Slurm"),
    Command(("info",), "Environment", "Show the image's components, resources, GPU and CVMFS"),
)


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
        "Standalone commands scigethelpers-cite and scigethelpers-kernel also work.",
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


# --- check -----------------------------------------------------------------

@dataclass(frozen=True)
class Result:
    status: str  # PASS, FAIL or SKIP
    detail: str


def run(argv: Sequence[str], timeout: float) -> subprocess.CompletedProcess[str] | None:
    """Run argv; return None, without blocking forever, after timeout."""
    try:
        process = subprocess.Popen(list(argv), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True)
    except OSError as error:
        return subprocess.CompletedProcess(list(argv), 127, "", str(error))
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        # A process in uninterruptible CVMFS I/O cannot exit, and a descendant
        # can hold its pipes open, so signal the group, close pipes, and reap
        # briefly before abandoning it.
        with suppress(OSError):
            os.killpg(process.pid, 9)
        for stream in (process.stdout, process.stderr):
            if stream is not None:
                with suppress(OSError):
                    stream.close()
        with suppress(subprocess.TimeoutExpired):
            process.wait(timeout=1)
        return None
    return subprocess.CompletedProcess(list(argv), process.returncode, stdout, stderr)


def first_line(text: str) -> str:
    return next((line.strip() for line in text.splitlines() if line.strip()), "no output")


def configured_cvmfs_repos() -> list[str]:
    """CVMFS repositories configured for this session, or an empty list."""
    raw = os.environ.get("SCIDESKTOP_CVMFS_REPOSITORIES", "").strip()
    if raw:
        return [r.strip() for r in raw.split(",") if r.strip()]
    repos: list[str] = []
    if CVMFS_CONFIG_DIR.is_dir():
        for conf in sorted(CVMFS_CONFIG_DIR.glob("*.conf")):
            if conf.name != "default.conf":
                repos.append(conf.stem)
    if not repos and CVMFS_ROOT.is_dir():
        with suppress(OSError):
            repos = sorted(p.name for p in CVMFS_ROOT.iterdir() if p.is_dir())
    return repos


# A hung FUSE mount blocks the caller forever, so every CVMFS read happens in
# a child process that a timeout can abandon.
CVMFS_PROBE = """
import os, sys
root = sys.argv[1]
entries = os.listdir(root)
modules = os.path.join(root, "neurodesk-modules")
count = len(os.listdir(modules)) if os.path.isdir(modules) else len(entries)
kind = "module categories" if os.path.isdir(modules) else "entries"
print(f"{count}\\t{kind}")
try:
    print(os.getxattr(root, "user.host").decode().strip())
except OSError:
    print("")
"""


def probe_cvmfs(repo: str, timeout: float = 60) -> tuple[int, str, str] | str:
    """Return (count, kind, active server) or a failure description."""
    repo_path = CVMFS_ROOT / repo
    result = run([sys.executable, "-I", "-c", CVMFS_PROBE, str(repo_path)], timeout)
    if result is None:
        return f"no response from {repo_path} within {timeout:.0f} s"
    if result.returncode != 0:
        return f"{repo_path} is not readable"
    first, _, host = result.stdout.partition("\n")
    count_str, _, kind = first.partition("\t")
    return int(count_str), kind or "entries", host.strip()


def check_cvmfs() -> Result:
    if os.environ.get("SCIDESKTOP_CVMFS_MODE") == "disabled":
        return Result("SKIP", "CVMFS is disabled (SCIDESKTOP_CVMFS_MODE=disabled)")
    repos = configured_cvmfs_repos()
    if not repos:
        return Result("SKIP", "no CVMFS repository configured in this image")
    repo = repos[0]
    probed = probe_cvmfs(repo)
    if isinstance(probed, str):
        return Result("FAIL", probed)
    count, kind, host = probed
    if count == 0:
        return Result("FAIL", f"{CVMFS_ROOT / repo} is empty")
    server = f" from {host}" if host else ""
    return Result("PASS", f"{repo}: {count} {kind}{server}")


def nvidia_devices() -> list[str]:
    if shutil.which("nvidia-smi") is None:
        return []
    result = run(["nvidia-smi", "-L"], 30)
    if result is None or result.returncode != 0:
        return []
    return [line for line in result.stdout.splitlines() if line.startswith("GPU ")]


def check_gpu() -> Result:
    devices = nvidia_devices()
    if not devices:
        return Result("SKIP", "no NVIDIA GPU visible in this container")
    return Result("PASS", f"{len(devices)} NVIDIA device(s)")


def check_slurm() -> Result:
    if shutil.which("sinfo") is None:
        return Result("SKIP", "Slurm is not installed")
    result = run(["sinfo", "--noheader", "--format=%P %t"], 15)
    if result is None:
        return Result("FAIL", "sinfo timed out; the controller may still be starting")
    if result.returncode != 0:
        return Result("FAIL", first_line(result.stderr))
    partitions = [line.split()[0] for line in result.stdout.splitlines() if line.split()]
    return Result("PASS", f"partitions: {', '.join(dict.fromkeys(partitions)) or 'none'}")


CHECKS: dict[str, Callable[[], Result]] = {
    "cvmfs": check_cvmfs,
    "gpu": check_gpu,
    "slurm": check_slurm,
}

CHECK_HELP = f"""usage: scigethelpers check [{' | '.join(CHECKS)}] ...

Run read-only health checks; with no names, run all of them.
Each check prints PASS, FAIL or SKIP. The exit status is 1 when a check fails.

  cvmfs  configured CVMFS repository is mounted and readable
  gpu    an NVIDIA GPU is visible
  slurm  the Slurm controller answers and lists partitions
"""


def command_check(args: Sequence[str]) -> int:
    if any(arg in {"-h", "--help"} for arg in args):
        print(CHECK_HELP, end="")
        return 0
    unknown_names = [name for name in args if name not in CHECKS]
    if unknown_names:
        print(f"scigethelpers check: unknown check '{unknown_names[0]}'. "
              f"Choose from: {', '.join(CHECKS)}.", file=sys.stderr)
        return 2
    names = list(dict.fromkeys(args)) or list(CHECKS)
    failed = False
    for name in names:
        result = CHECKS[name]()
        failed |= result.status == "FAIL"
        print(f"[{result.status}] {name:<6} {result.detail}", flush=True)
    return 1 if failed else 0


# --- info ------------------------------------------------------------------

def read_text(path: str) -> str:
    try:
        return Path(path).read_text().strip()
    except OSError:
        return ""


def read_resource_limits() -> dict[str, str]:
    """Read CPU_LIMIT and MEM_LIMIT from env or startup's /opt/scidesktop/resource-limits."""
    limits = {k: os.environ[k].strip() for k in ("CPU_LIMIT", "MEM_LIMIT") if os.environ.get(k, "").strip()}
    helper = Path("/opt/scidesktop/resource-limits")
    if len(limits) < 2 and os.access(helper, os.X_OK):
        result = run([str(helper)], 5)
        if result is not None and result.returncode == 0:
            for line in result.stdout.splitlines():
                key, sep, val = line.partition("=")
                if sep and key in ("CPU_LIMIT", "MEM_LIMIT") and val.strip():
                    limits.setdefault(key, val.strip())
    return limits


def memory_limit() -> str:
    total_kib = next((int(line.split()[1]) for line in read_text("/proc/meminfo").splitlines()
                      if line.startswith("MemTotal:")), 0)
    limit_bytes = total_kib * 1024
    raw = read_resource_limits().get("MEM_LIMIT", "")
    if raw.isdigit() and int(raw) > 0:
        limit_bytes = min(limit_bytes, int(raw)) if limit_bytes else int(raw)
    return f"{limit_bytes / 2**30:.1f} GiB" if limit_bytes else "unknown"


def cpu_limit() -> str:
    available = len(os.sched_getaffinity(0))
    raw = read_resource_limits().get("CPU_LIMIT", "")
    try:
        if raw and float(raw) > 0:
            return f"{min(float(available), float(raw)):g}"
    except ValueError:
        pass
    return str(available)


def image_components() -> str:
    """The image's components, as its manifest names them."""
    return ", ".join(sorted(path.stem for path in MANIFESTS.glob("*.json"))) or "unknown"


def command_info(args: Sequence[str]) -> int:
    if args:
        print("usage: scigethelpers info\n\nShow the image's components, resources, GPU and CVMFS state.",
              file=sys.stdout if args[0] in {"-h", "--help"} else sys.stderr)
        return 0 if args[0] in {"-h", "--help"} else 2
    rows = [
        ("Image", image_components()),
        ("User", f"{os.environ.get('USER') or os.getuid()} (home {Path.home()})"),
        ("CPUs", cpu_limit()),
        ("Memory", memory_limit()),
    ]
    usage_ = shutil.disk_usage(Path.home())
    rows.append(("Home", f"{usage_.free / 2**30:.1f} GiB free of {usage_.total / 2**30:.1f} GiB"))
    rows.append(("GPU", "; ".join(nvidia_devices()) or "none visible"))
    if os.environ.get("SCIDESKTOP_CVMFS_MODE") == "disabled":
        rows.append(("CVMFS", "disabled"))
    else:
        repos = configured_cvmfs_repos()
        if not repos:
            rows.append(("CVMFS", "not configured"))
        else:
            probed = probe_cvmfs(repos[0], timeout=20)
            rows.append(("CVMFS", probed if isinstance(probed, str) else
                         f"{repos[0]} mounted, server {probed[2] or 'unknown'}"))
    width = max(len(label) for label, _ in rows) + 1
    for label, value in rows:
        print(f"{label + ':':<{width}} {value}")
    return 0


# --- dispatch ----------------------------------------------------------------

def main(argv: Sequence[str] | None = None,
         execv: Callable[[str, list[str]], object] = os.execv) -> int:
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
    if command.name == "check":
        return command_check(rest)
    if command.name == "info":
        return command_info(rest)
    assert command.executable is not None
    target = BIN_DIR / command.executable
    if not os.access(target, os.X_OK):
        print(f"scigethelpers {command.name}: {target} is not installed in this image.", file=sys.stderr)
        return 1
    execv(str(target), [str(target), *rest])
    return 0


if __name__ == "__main__":
    sys.exit(main())
