#!/opt/conda/bin/python3 -I
"""Write a citation list for the container tools this user has loaded.

Generalized from neurodesk/neurodesktop (config/jupyter/neurodesk_cite.py, MIT,
Copyright (c) 2021 NeuroDesk; /opt/scigethelpers-cli/LICENSE) to work with any
sciget catalog (neuroimaging, microscopy, and others).

The Lmod site package (/opt/scigethelpers-cli/lmod/SitePackage.lua) appends one
line per loaded container module to the usage log. This command resolves those
modules against the image's configured sciget catalogs (/etc/sciget/catalogs.json
and ~/.config/sciget/catalogs.json) and writes CITATIONS.md with methods
sentences and references grouped by tool.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime
from pathlib import Path

FALLBACK_CATALOGUE_URL = "https://apps-catalog.scigetorg.workers.dev/neuroimaging/apps.json"
SYSTEM_CATALOGS = Path("/etc/sciget/catalogs.json")
CITATION_GUIDE_URL = "https://neurodesk.org/overview/how-to-cite-us/"
RECIPES_URL = "https://github.com/neurodesk/neurocontainers/tree/main/recipes"
NEURODESK_REFERENCE = (
    "Renton, A.I., Dao, T.T., Johnstone, T., Civier, O., Sullivan, R. P., "
    "White, D. J., ... Narayanan, A. & Bollmann, S. Neurodesk: an accessible, "
    "flexible and portable data analysis environment for reproducible "
    "neuroimaging. Nat Methods (2024). https://doi.org/10.1038/s41592-023-02145-x"
)
AEDAPT_NOTE = (
    "You used EEG/MEG/electrophysiology tools. Please also cite the AEDAPT "
    'project, for example by adding "part of the AEDAPT project" to the '
    "methods sentence. See " + CITATION_GUIDE_URL
)
TIMESTAMP_FORMAT = "%Y-%m-%dT%H:%M:%SZ"
FETCH_TIMEOUT_SECONDS = 15
USER_AGENT = "scigethelpers-cite"
"""The catalogue host's bot filter rejects urllib's default ``Python-urllib`` agent."""


@dataclass(frozen=True)
class ModuleUse:
    """One `module load` of a container module, as recorded by the Lmod hook."""

    name: str
    version: str
    loaded_at: datetime


@dataclass(frozen=True)
class CatalogueEntry:
    tool: str
    build_date: date
    citation: str | None
    electrophysiology: bool


ModuleKey = tuple[str, str]
"""An Lmod module's ``(name, version)``, as recorded in the usage log."""

Catalogue = Mapping[ModuleKey, CatalogueEntry]


@dataclass(frozen=True)
class ToolCitation:
    """A tool version that was used; ``entry`` is None when the catalogue lacks it."""

    name: str
    version: str
    entry: CatalogueEntry | None

    @property
    def recipe_url(self) -> str:
        tool = self.entry.tool if self.entry is not None else self.name
        return f"{RECIPES_URL}/{tool.removesuffix('_arm64')}"

    @property
    def reference(self) -> str:
        if self.entry is not None and self.entry.citation:
            return self.entry.citation
        return (
            f"{self.name}: the tool catalogue does not list a citation yet. "
            f"See {CITATION_GUIDE_URL} and the recipe at {self.recipe_url}"
        )

    def methods_sentence(self, image_version: str) -> str:
        built = f", built {self.entry.build_date.isoformat()}" if self.entry else ""
        return (
            f"{self.name} (v{self.version}{built}) was run in Neurodesk/Scidesktop "
            f"({'v' + image_version + ', ' if image_version else ''}Renton et al., 2024)."
        )


def parse_usage_log(text: str) -> list[ModuleUse]:
    """Parse ``name<TAB>version<TAB>timestamp`` lines, skipping malformed ones."""
    uses = []
    for line in text.splitlines():
        fields = line.split("\t")
        if len(fields) != 3 or not fields[0]:
            continue
        try:
            loaded_at = datetime.strptime(fields[2], TIMESTAMP_FORMAT)
        except ValueError:
            continue
        uses.append(ModuleUse(fields[0], fields[1], loaded_at.replace(tzinfo=UTC)))
    return uses


def parse_catalogue(document: object) -> dict[ModuleKey, CatalogueEntry]:
    """Index apps.json apps by the Lmod module of their image, keeping the newest build."""
    catalogue: dict[ModuleKey, CatalogueEntry] = {}
    tools = document.items() if isinstance(document, dict) else []
    for tool_key, tool in tools:
        if not isinstance(tool, dict) or not isinstance(tool.get("apps"), dict):
            continue
        text = tool.get("citation")
        citation = (text.strip() or None) if isinstance(text, str) else None
        categories = tool.get("categories")
        electrophysiology = (
            isinstance(categories, list) and "electrophysiology" in categories
        )
        for app in tool["apps"].values():
            if not isinstance(app, dict):
                continue
            image, stamp = app.get("image"), app.get("version")
            if not isinstance(image, str) or not isinstance(stamp, str):
                continue
            name, _, version = image.rpartition("_")
            if not name:
                continue
            try:
                build_date = datetime.strptime(stamp, "%Y%m%d").date()
            except ValueError:
                continue
            entry = CatalogueEntry(tool_key, build_date, citation, electrophysiology)
            known = catalogue.get((name, version))
            if known is None or known.build_date < entry.build_date:
                catalogue[(name, version)] = entry
    return catalogue


def resolve(uses: Iterable[ModuleUse], catalogue: Catalogue) -> list[ToolCitation]:
    """One citation per tool version, in order of first use."""
    tools: dict[tuple[str, str], ToolCitation] = {}
    for use in uses:
        key = (use.name, use.version)
        if key not in tools:
            tools[key] = ToolCitation(use.name, use.version, catalogue.get(key))
    return list(tools.values())


def render(
    tools: Sequence[ToolCitation], image_version: str, uses: Sequence[ModuleUse]
) -> str:
    first = min(use.loaded_at for use in uses).date().isoformat()
    last = max(use.loaded_at for use in uses).date().isoformat()
    period = f"on {first}" if first == last else f"between {first} and {last}"
    lines = [
        "# Citations for container tools",
        "",
        f"Generated by `scigethelpers cite` from {len(uses)} recorded module loads {period}. "
        "Remove any tool your analysis did not use.",
        "",
        "## Methods",
        "",
    ]
    lines += [tool.methods_sentence(image_version) for tool in tools]
    if any(tool.entry is not None and tool.entry.electrophysiology for tool in tools):
        lines += ["", AEDAPT_NOTE]
    references: dict[str, dict[str, None]] = {}
    for tool in tools:
        name = tool.entry.tool if tool.entry is not None else tool.name
        name = name.removesuffix("_arm64")
        references.setdefault(name, {})[tool.reference] = None
    lines += ["", "## References", ""]
    for name in sorted(references, key=str.casefold):
        lines += [f"### {name}", ""]
        for reference in references[name]:
            lines += [reference, ""]
    lines += ["### Neurodesk", "", NEURODESK_REFERENCE, ""]
    return "\n".join(lines)


def state_base() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")


def state_dir() -> Path:
    return state_base() / "scigethelpers"


def legacy_log() -> Path:
    return state_base() / "neurodesk/module-usage.tsv"


def cache_dir() -> Path:
    return (
        Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "scigethelpers"
    )


def default_output() -> Path:
    return Path.home() / "CITATIONS.md"


def configured_catalogue_urls() -> list[str]:
    """Active catalog URLs from sciget's system and user configuration."""
    override = (
        os.environ.get("SCIGETHELPERS_CITE_CATALOGUE_URL")
        or os.environ.get("NEURODESKTOP_CITE_CATALOGUE_URL")
    )
    if override:
        return [u.strip() for u in override.split(",") if u.strip()]
    config_base = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    by_name: dict[str, tuple[bool, str]] = {}
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
            prev_use, prev_url = by_name.get(name, (True, ""))
            use = bool(entry["use"]) if "use" in entry else prev_use
            url = entry["url"] if isinstance(entry.get("url"), str) else prev_url
            by_name[name] = (use, url)
    urls = [url for use, url in by_name.values() if use and url]
    return urls or [FALLBACK_CATALOGUE_URL]


def write_atomically(path: Path, text: str) -> None:
    """Replace *path* in one step; the file gets the usual umask permissions."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, path)


def load_one_catalogue(url: str, cache: Path) -> dict[ModuleKey, CatalogueEntry]:
    """Fetch one catalogue, refreshing its cache, or fall back to the cache."""
    try:
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=FETCH_TIMEOUT_SECONDS) as response:
            raw = response.read().decode("utf-8")
        catalogue = parse_catalogue(json.loads(raw))
    except (OSError, ValueError) as error:
        try:
            cached = cache.read_text(encoding="utf-8")
            catalogue = parse_catalogue(json.loads(cached))
        except (OSError, ValueError):
            print(
                f"Could not fetch {url} ({error}) and no cached catalogue exists.",
                file=sys.stderr,
            )
            print(
                "Build dates and tool citations are missing from the output.",
                file=sys.stderr,
            )
            return {}
        fetched = datetime.fromtimestamp(cache.stat().st_mtime).date().isoformat()
        print(
            f"Could not fetch {url} ({error}); using the catalogue cached on {fetched}.",
            file=sys.stderr,
        )
        return catalogue
    try:
        write_atomically(cache, raw)
    except OSError as error:
        print(f"Could not cache the catalogue in {cache}: {error}", file=sys.stderr)
    return catalogue


def load_catalogues(urls: Sequence[str]) -> dict[ModuleKey, CatalogueEntry]:
    merged: dict[ModuleKey, CatalogueEntry] = {}
    root = cache_dir()
    for url in urls:
        key = hashlib.sha256(url.encode("utf-8")).hexdigest()[:12]
        for mod_key, entry in load_one_catalogue(url, root / f"apps-{key}.json").items():
            known = merged.get(mod_key)
            if known is None or known.build_date < entry.build_date:
                merged[mod_key] = entry
    return merged


def parse_args(argv: Sequence[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="scigethelpers cite",
        description="Write CITATIONS.md for the container tools you loaded with ml, notebooks or the menu.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="file to write (default: CITATIONS.md in the home folder)",
    )
    parser.add_argument(
        "--since",
        type=date.fromisoformat,
        metavar="YYYY-MM-DD",
        help="only include loads on or after this date",
    )
    parser.add_argument(
        "--clear", action="store_true", help="empty the usage log and exit"
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    log = state_dir() / "module-usage.tsv"
    if args.clear:
        for path in (log, legacy_log()):
            if path.exists():
                path.write_text("")
        print(f"Cleared {log}.")
        return 0
    uses: list[ModuleUse] = []
    for path in (legacy_log(), log):
        try:
            uses.extend(parse_usage_log(path.read_text(encoding="utf-8", errors="replace")))
        except FileNotFoundError:
            pass
    if args.since is not None:
        uses = [use for use in uses if use.loaded_at.date() >= args.since]
    if not uses:
        print(f"No container module loads are recorded in {log}.", file=sys.stderr)
        print(
            "Load a tool with ml, a notebook or the Applications menu, then run scigethelpers cite again.",
            file=sys.stderr,
        )
        return 1
    tools = resolve(uses, load_catalogues(configured_catalogue_urls()))
    # A deployment that versions its image names it here.
    version = os.environ.get("SCIDESKTOP_VERSION") or os.environ.get("NEURODESKTOP_VERSION") or ""
    output = args.output or default_output()
    try:
        write_atomically(output, render(tools, version, uses))
    except OSError as error:
        print(f"Could not write {output}: {error}", file=sys.stderr)
        return 1
    for tool in tools:
        if tool.entry is None:
            print(
                f"{tool.name}/{tool.version} is not in the configured tool catalogue.",
                file=sys.stderr,
            )
    print(f"Wrote citations for {len(tools)} tool versions to {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
