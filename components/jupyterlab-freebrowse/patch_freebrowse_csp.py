#!/usr/bin/env python3
"""Allow same-origin JupyterLab iframe embedding for FreeBrowse under JupyterHub.

JupyterHub sets `Content-Security-Policy: frame-ancestors 'none'` on the
single-user server by default. FreeBrowse renders inside a JupyterLab iframe,
so its static handler needs `frame-ancestors 'self'` while preserving all other
CSP directives and keeping `'none'` on the rest of the server.
"""

from pathlib import Path
import sys

BEFORE = '''class FreeBrowseStaticHandler(JupyterHandler, StaticFileHandler):
    """Authenticated, packaged application assets, never user workspace files."""'''

AFTER = '''def _allow_same_origin_framing(csp: str) -> str:
    """scidesktop-freebrowse-csp: allow same-origin framing while keeping other CSP policies/directives."""
    policies = []
    any_replaced = False
    for raw_policy in csp.split(","):
        directives = []
        replaced = False
        for raw in raw_policy.split(";"):
            directive = raw.strip()
            if not directive:
                continue
            name = directive.split(None, 1)[0].lower()
            if name == "frame-ancestors":
                if not replaced:
                    directives.append("frame-ancestors 'self'")
                    replaced = True
                    any_replaced = True
            else:
                directives.append(directive)
        if directives:
            policies.append("; ".join(directives))
    if not any_replaced:
        if policies:
            policies[0] = f"{policies[0]}; frame-ancestors 'self'"
        else:
            policies.append("frame-ancestors 'self'")
    return ", ".join(policies)


class FreeBrowseStaticHandler(JupyterHandler, StaticFileHandler):
    """Authenticated, packaged application assets, never user workspace files."""

    @property
    def content_security_policy(self):
        return _allow_same_origin_framing(super().content_security_policy)'''


def patch_handlers(path: Path) -> bool:
    source = path.read_text(encoding="utf-8")
    if "scidesktop-freebrowse-csp" in source:
        return False
    if source.count(BEFORE) != 1:
        raise ValueError("FreeBrowseStaticHandler anchor changed; reassess CSP patch")
    patched = source.replace(BEFORE, AFTER)
    compile(patched, str(path), "exec")
    path.write_text(patched, encoding="utf-8")
    return True


if __name__ == "__main__":
    patch_handlers(Path(sys.argv[1]))
