"""Authenticated Tornado API handlers for the Session Helpers JupyterLab panel.

Every endpoint delegates to `/usr/local/bin/scigethelpers` in an async child
process with its own process group, bounded output, aligned deadlines, and
single-flight locks for probe/write actions so Tornado's event loop is never
blocked and a hung CVMFS mount cannot wedge the notebook server.
"""

from __future__ import annotations

import asyncio
import atexit
from contextlib import suppress
import json
import os
from pathlib import Path
import signal
from typing import Any
from urllib.parse import urlparse

from jupyter_server.auth.decorator import authorized
from jupyter_server.base.handlers import APIHandler
from jupyter_server.utils import url_path_join
from tornado import web

SCIGETHELPERS = "/usr/local/bin/scigethelpers"
MANIFESTS = Path("/opt/scidesktop/manifest.d")
ALLOWED_CHECKS = ("cvmfs", "gpu", "slurm", "t3")
MAX_BODY_BYTES = 16 * 1024
MAX_STDOUT_BYTES = 512 * 1024
MAX_STDERR_BYTES = 64 * 1024

_active_pgids: set[int] = set()
_action_locks: dict[str, asyncio.Lock] = {}


def _cleanup_active_children() -> None:
    for pgid in list(_active_pgids):
        with suppress(OSError):
            os.killpg(pgid, signal.SIGTERM)
    _active_pgids.clear()


atexit.register(_cleanup_active_children)


def _lock_for(action: str) -> asyncio.Lock:
    lock = _action_locks.get(action)
    if lock is None:
        lock = asyncio.Lock()
        _action_locks[action] = lock
    return lock


async def _read_bounded(stream: asyncio.StreamReader | None, limit: int) -> bytes:
    if stream is None:
        return b""
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = await stream.read(16384)
        if not chunk:
            break
        if total < limit:
            chunks.append(chunk[: max(0, limit - total)])
            total += len(chunk)
    return b"".join(chunks)


async def _run_cli(
    argv: list[str], timeout: float, *, deadline_seconds: float | None = None
) -> tuple[int, str, str]:
    """Run an allowlisted CLI invocation in its own process group with timeouts."""
    env = dict(os.environ)
    if deadline_seconds is not None:
        env["SCIGETHELPERS_DEADLINE_SECONDS"] = str(deadline_seconds)
    proc = await asyncio.create_subprocess_exec(
        *argv,
        stdin=asyncio.subprocess.DEVNULL,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        start_new_session=True,
        env=env,
    )
    pgid = proc.pid
    _active_pgids.add(pgid)
    try:
        stdout_task = asyncio.create_task(_read_bounded(proc.stdout, MAX_STDOUT_BYTES))
        stderr_task = asyncio.create_task(_read_bounded(proc.stderr, MAX_STDERR_BYTES))
        try:
            await asyncio.wait_for(proc.wait(), timeout=timeout)
        except asyncio.TimeoutError:
            # Send SIGTERM first so scigethelpers_cli's signal handler kills
            # every detached probe child process group cleanly before SIGKILL.
            with suppress(OSError):
                os.killpg(pgid, signal.SIGTERM)
            with suppress(asyncio.TimeoutError):
                await asyncio.wait_for(proc.wait(), timeout=2)
            with suppress(OSError):
                os.killpg(pgid, signal.SIGKILL)
            with suppress(asyncio.TimeoutError):
                await asyncio.wait_for(proc.wait(), timeout=1)
            stdout_task.cancel()
            stderr_task.cancel()
            return 124, "", f"command timed out after {timeout:.0f} s"
        stdout_b = await stdout_task
        stderr_b = await stderr_task
        return (
            proc.returncode or 0,
            stdout_b.decode("utf-8", "replace"),
            stderr_b.decode("utf-8", "replace"),
        )
    finally:
        _active_pgids.discard(pgid)


def _tail_error(stderr: str, fallback: str) -> str:
    text = stderr.strip()
    if not text:
        return fallback
    lines = text.splitlines()
    return "\n".join(lines[-8:])[:4000]


def _relative_to_root(path_str: str | None, root_dir: Path) -> str | None:
    """Return POSIX path relative to Jupyter's root_dir, or None if outside."""
    if not path_str:
        return None
    try:
        target = Path(path_str).expanduser().resolve(strict=False)
        root = root_dir.expanduser().resolve(strict=False)
        if not target.is_relative_to(root):
            return None
        return target.relative_to(root).as_posix()
    except OSError:
        return None


def _default_citations_path() -> Path:
    return Path.home() / "CITATIONS.md"


class _BaseHelpersHandler(APIHandler):
    def set_default_headers(self) -> None:
        super().set_default_headers()
        self.set_header("Cache-Control", "no-store")

    def _root_dir(self) -> Path:
        root = getattr(self.contents_manager, "root_dir", None) or self.settings.get("server_root_dir")
        return Path(root or Path.home())

    def _require_same_origin(self) -> None:
        """Refuse cross-origin or originless cookie-authenticated POSTs.

        Checks the Origin host strictly against the request's Host header
        rather than inheriting Jupyter's CORS allow_origin/allow_origin_pat.
        """
        if self.token_authenticated:
            return
        origin = self.request.headers.get("Origin")
        if not origin:
            raise web.HTTPError(403, "Missing Origin header on cookie-authenticated POST")
        parsed = urlparse(origin)
        host = (self.request.host or "").lower()
        if parsed.scheme not in ("http", "https") or not parsed.netloc or parsed.netloc.lower() != host:
            raise web.HTTPError(403, "Cross-origin POST request rejected")

    def _read_json_body(self, allowed_keys: set[str]) -> dict[str, Any]:
        raw = self.request.body or b""
        if len(raw) > MAX_BODY_BYTES:
            raise web.HTTPError(413, "Request body too large")
        if not raw.strip():
            return {}
        try:
            data = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, ValueError) as error:
            raise web.HTTPError(400, f"Invalid JSON body: {error}") from None
        if not isinstance(data, dict):
            raise web.HTTPError(400, "JSON body must be an object")
        unknown = set(data) - allowed_keys
        if unknown:
            raise web.HTTPError(400, f"Unknown field(s): {', '.join(sorted(unknown))}")
        return data


class OverviewHandler(_BaseHelpersHandler):
    """Fast, strictly local read-only snapshot of session helpers state."""

    auth_resource = "status"

    @web.authenticated
    @authorized("read", "status")
    async def get(self) -> None:
        info_task = _run_cli([SCIGETHELPERS, "info", "--no-probes", "--json"], timeout=15)
        cite_task = _run_cli([SCIGETHELPERS, "cite", "--status", "--json"], timeout=15)
        kernel_task = _run_cli([SCIGETHELPERS, "kernel", "list", "--json"], timeout=15)
        uv_task = _run_cli([SCIGETHELPERS, "uv", "list", "--json"], timeout=15)

        (info_rc, info_out, _), (cite_rc, cite_out, _), (k_rc, k_out, _), (uv_rc, uv_out, _) = (
            await asyncio.gather(info_task, cite_task, kernel_task, uv_task)
        )

        def parse_dict(rc: int, out: str) -> dict[str, Any]:
            if rc != 0:
                return {}
            try:
                parsed = json.loads(out)
                return parsed if isinstance(parsed, dict) else {}
            except ValueError:
                return {}

        info = parse_dict(info_rc, info_out)
        cite = parse_dict(cite_rc, cite_out)
        raw_kernels = parse_dict(k_rc, k_out).get("kernels")
        raw_uv = parse_dict(uv_rc, uv_out).get("kernels")
        kernels = raw_kernels if isinstance(raw_kernels, list) else []
        uv_kernels = raw_uv if isinstance(raw_uv, list) else []

        root_dir = self._root_dir()
        if cite.get("citations_path"):
            cite["relative_path"] = _relative_to_root(str(cite["citations_path"]), root_dir)

        getting_started = root_dir / "getting-started.ipynb"
        getting_started_rel = "getting-started.ipynb" if getting_started.is_file() else None
        t3_connect_available = (MANIFESTS / "t3-connect.json").is_file()

        self.finish(json.dumps({
            "info": info,
            "citations": cite,
            "container_kernels": kernels,
            "uv_kernels": uv_kernels,
            "links": {
                "getting_started": getting_started_rel,
                "t3_connect": "t3-connect/" if t3_connect_available else None,
            },
        }))


class InfoHandler(_BaseHelpersHandler):
    """On-demand full `scigethelpers info --json` (includes GPU & CVMFS probes)."""

    auth_resource = "status"

    @web.authenticated
    @authorized("read", "status")
    async def post(self) -> None:
        self._require_same_origin()
        self._read_json_body(set())
        lock = _lock_for("info")
        if lock.locked():
            raise web.HTTPError(409, "An environment info probe is already running")
        async with lock:
            rc, out, err = await _run_cli(
                [SCIGETHELPERS, "info", "--json"],
                timeout=35,
                deadline_seconds=25,
            )
        if rc != 0:
            raise web.HTTPError(500, _tail_error(err, f"scigethelpers info failed (exit {rc})"))
        try:
            payload = json.loads(out)
        except ValueError:
            raise web.HTTPError(500, "scigethelpers info returned invalid JSON") from None
        self.finish(json.dumps(payload))


class CheckHandler(_BaseHelpersHandler):
    """On-demand `scigethelpers check --json` for allowlisted targets."""

    auth_resource = "status"

    @web.authenticated
    @authorized("read", "status")
    async def post(self) -> None:
        self._require_same_origin()
        body = self._read_json_body({"checks"})
        selected: list[str] = []
        if "checks" in body:
            raw_checks = body["checks"]
            if not isinstance(raw_checks, list) or not all(isinstance(c, str) for c in raw_checks):
                raise web.HTTPError(400, "'checks' must be a list of check names")
            bad = [c for c in raw_checks if c not in ALLOWED_CHECKS]
            if bad:
                raise web.HTTPError(400, f"Unknown check(s): {', '.join(bad)}")
            selected = list(dict.fromkeys(raw_checks))
        lock = _lock_for("check")
        if lock.locked():
            raise web.HTTPError(409, "An environment check is already running")
        argv = [SCIGETHELPERS, "check", "--json", *selected]
        async with lock:
            rc, out, err = await _run_cli(argv, timeout=75, deadline_seconds=60)
        if rc not in (0, 1):
            raise web.HTTPError(500, _tail_error(err, f"scigethelpers check failed (exit {rc})"))
        try:
            payload = json.loads(out)
        except ValueError:
            raise web.HTTPError(500, "scigethelpers check returned invalid JSON") from None
        self.finish(json.dumps(payload))


class CiteHandler(_BaseHelpersHandler):
    """Explicit user action to generate CITATIONS.md at the fixed default path."""

    auth_resource = "contents"

    @web.authenticated
    @authorized("write", "contents")
    async def post(self) -> None:
        self._require_same_origin()
        body = self._read_json_body({"action", "overwrite"})
        action = body.get("action", "generate")
        if action != "generate":
            raise web.HTTPError(400, f"Unsupported action: {action!r}")
        overwrite = body.get("overwrite", False)
        if not isinstance(overwrite, bool):
            raise web.HTTPError(400, "'overwrite' must be a boolean")

        lock = _lock_for("cite")
        if lock.locked():
            raise web.HTTPError(409, "Citation generation is already running")
        async with lock:
            target = _default_citations_path()
            if target.exists() and not overwrite:
                self.set_status(409)
                self.finish(json.dumps({
                    "ok": False,
                    "needs_overwrite": True,
                    "output": str(target),
                    "relative_path": _relative_to_root(str(target), self._root_dir()),
                    "error": f"{target} already exists; confirm overwrite to replace it.",
                }))
                return
            argv = [SCIGETHELPERS, "cite", "--json"]
            if not overwrite:
                argv.append("--no-clobber")
            rc, out, err = await _run_cli(argv, timeout=45)
        try:
            payload = json.loads(out) if out.strip() else {}
        except ValueError:
            payload = {}
        if rc != 0:
            if isinstance(payload, dict) and payload.get("ok") is False:
                payload["relative_path"] = _relative_to_root(
                    str(payload.get("output") or ""), self._root_dir()
                )
                if payload.get("needs_overwrite") is True:
                    self.set_status(409)
                self.finish(json.dumps(payload))
                return
            raise web.HTTPError(500, _tail_error(err, f"scigethelpers cite failed (exit {rc})"))
        if isinstance(payload, dict):
            payload["relative_path"] = _relative_to_root(
                str(payload.get("output") or ""), self._root_dir()
            )
        self.finish(json.dumps(payload))


def setup_handlers(server_app: Any) -> None:
    web_app = server_app.web_app
    base_url = web_app.settings["base_url"]
    handlers = [
        (url_path_join(base_url, "scigethelpers/api/overview"), OverviewHandler),
        (url_path_join(base_url, "scigethelpers/api/info"), InfoHandler),
        (url_path_join(base_url, "scigethelpers/api/check"), CheckHandler),
        (url_path_join(base_url, "scigethelpers/api/cite"), CiteHandler),
    ]
    web_app.add_handlers(".*$", handlers)
