"""Tornado handler for operator-configured external JupyterLab launcher links."""

import json
import os
import re
from urllib.parse import urlparse

from jupyter_server.base.handlers import APIHandler
from jupyter_server.utils import url_path_join
from tornado.web import authenticated

WEBKNOSSOS_ENV = "SCIDESKTOP_WEBKNOSSOS_URL"
LINKS_ENV = "SCIDESKTOP_LAUNCHER_LINKS"
ALLOWED_ICONS = {"webknossos", "external"}


def _valid_http_url(raw: object) -> str | None:
    if not isinstance(raw, str):
        return None
    url = raw.strip()
    if not url or len(url) > 2048 or any(ord(ch) <= 0x20 or ord(ch) == 0x7F for ch in url):
        return None
    try:
        parsed = urlparse(url)
        _ = parsed.port
    except ValueError:
        return None
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        return None
    return url


def _slug(text: str) -> str:
    return re.sub(r"[^a-z0-9-]+", "-", text.lower()).strip("-") or "link"


def collect_links(environ=None, log=None) -> list[dict]:
    """Read validated external launcher links from the container environment."""
    env = os.environ if environ is None else environ
    links: list[dict] = []
    seen_ids: set[str] = set()

    wk_raw = env.get(WEBKNOSSOS_ENV, "")
    if wk_raw.strip():
        wk_url = _valid_http_url(wk_raw)
        if wk_url:
            links.append(
                {
                    "id": "webknossos",
                    "title": "WEBKNOSSOS",
                    "caption": "Open WEBKNOSSOS 3D microscopy viewer and annotation platform",
                    "url": wk_url,
                    "category": "Scidesktop",
                    "icon": "webknossos",
                    "rank": 20,
                }
            )
            seen_ids.add("webknossos")
        elif log is not None:
            log.warning("launcher-links: ignoring invalid %s", WEBKNOSSOS_ENV)

    raw_json = env.get(LINKS_ENV, "").strip()
    if raw_json:
        try:
            parsed = json.loads(raw_json)
        except ValueError:
            if log is not None:
                log.warning("launcher-links: ignoring malformed %s JSON", LINKS_ENV)
            parsed = []
        if not isinstance(parsed, list):
            if log is not None:
                log.warning("launcher-links: %s must be a JSON array", LINKS_ENV)
            parsed = []
        for idx, item in enumerate(parsed):
            if not isinstance(item, dict):
                continue
            title = item.get("title")
            url = _valid_http_url(item.get("url"))
            if not isinstance(title, str) or not title.strip() or not url:
                continue
            title = title.strip()[:80]
            category = item.get("category")
            if not isinstance(category, str) or not category.strip():
                category = "Scidesktop"
            else:
                category = category.strip()[:60]
            caption = item.get("caption")
            if not isinstance(caption, str) or not caption.strip():
                caption = f"Open {title}"
            else:
                caption = caption.strip()[:200]
            icon = item.get("icon")
            if not isinstance(icon, str) or icon not in ALLOWED_ICONS:
                icon = "external"
            raw_id = item.get("id")
            base_id = _slug(raw_id) if isinstance(raw_id, str) and raw_id.strip() else _slug(title)
            link_id = base_id
            suffix = 2
            while link_id in seen_ids:
                link_id = f"{base_id}-{suffix}"
                suffix += 1
            seen_ids.add(link_id)
            rank = item.get("rank")
            if not isinstance(rank, int) or isinstance(rank, bool):
                rank = 30 + idx
            links.append(
                {
                    "id": link_id,
                    "title": title,
                    "caption": caption,
                    "url": url,
                    "category": category,
                    "icon": icon,
                    "rank": rank,
                }
            )
    return links


class LauncherLinksHandler(APIHandler):
    """Return the validated external launcher links configured for this session."""

    @authenticated
    def get(self):
        self.set_header("Cache-Control", "no-store")
        self.finish(json.dumps({"links": collect_links(log=self.log)}))


def setup_handlers(web_app, log=None):
    base_url = web_app.settings.get("base_url", "/")
    route = re.escape(url_path_join(base_url, "scidesktop-launcher-links", "links")) + r"$"
    web_app.add_handlers(r".*", [(route, LauncherLinksHandler)])
