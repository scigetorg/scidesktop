"""Build rfc3987_syntax's parsers on first use instead of at import.

rfc3987_syntax 1.1.0 compiles about 40 Earley parsers when imported. jsonschema
imports it as an optional format checker, and jupyter_events imports
jsonschema, so every Jupyter server start pays ~0.9 s for parsers it does not
use. Upstream: https://github.com/willynilly/rfc3987-syntax/issues/7 (and #8,
#11, #12).

The patch wraps each Lark parser in a proxy that builds it on first attribute
access. Behaviour is unchanged. It applies only to the exact upstream text and
reports when that text is not found, so a fixed upstream release is left alone.

    python rfc3987_syntax_lazy.py   # run with the environment's interpreter
"""
import importlib.util
import sys

spec = importlib.util.find_spec("rfc3987_syntax.syntax_helpers")
if spec is None:
    print("rfc3987_syntax not installed; nothing to patch")
    sys.exit(0)
path = spec.origin
src = open(path).read()

LAZY = '''

class _LazyLark:
    """A Lark parser built the first time it is used."""

    def __init__(self, **kwargs):
        self._kwargs = kwargs
        self._parser = None

    def __getattr__(self, name):
        if self._parser is None:
            self._parser = Lark(grammar, **self._kwargs)
        return getattr(self._parser, name)

'''
replacements = [
    ('syntax_parser = Lark(grammar, start=["iri", "iri_reference", "absolute_iri"], parser=RFC3987_SYNTAX_PARSER_TYPE)',
     LAZY + 'syntax_parser = _LazyLark(start=["iri", "iri_reference", "absolute_iri"], parser=RFC3987_SYNTAX_PARSER_TYPE)'),
    ('    parser = Lark(grammar, start=rule_name, parser=RFC3987_SYNTAX_PARSER_TYPE)',
     '    parser = _LazyLark(start=rule_name, parser=RFC3987_SYNTAX_PARSER_TYPE)'),
]
if "_LazyLark" in src:
    print(f"{path}: already patched")
    sys.exit(0)
if not all(src.count(old) == 1 for old, _ in replacements):
    print(f"{path}: upstream text changed; patch not applied")
    sys.exit(0)
for old, new in replacements:
    src = src.replace(old, new)
open(path, "w").write(src)

# The patched module must still validate correctly.
from rfc3987_syntax import is_valid_syntax, is_valid_syntax_iri

assert is_valid_syntax("iri", "https://example.org/a?b#c")
assert not is_valid_syntax("iri", "not an iri")
assert is_valid_syntax_iri("https://example.org/")
print(f"{path}: patched to build parsers on first use")
