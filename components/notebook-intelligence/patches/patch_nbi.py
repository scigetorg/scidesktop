#!/usr/bin/env python3
"""Build-time patches for the installed notebook_intelligence package.

Ported from neurodesk/neurodesktop (MIT). Anchored on the exact upstream code
and failing the image build loudly when the anchor no longer matches, so a
notebook_intelligence version bump cannot silently reintroduce the bug.

1. Settings panel refresh (labextension JS bundle):
   The upstream settings panel renders from the client-side capabilities cache
   fetched at page load and auto-saves its state on mount. Rewrites the "open
   settings" command to dispose any previously-built panel, await a fresh
   capabilities fetch, and only then build and show the panel.

2. Ollama context-length fallback (server-side provider):
   When `ollama list` returns an empty `details.family` (e.g. safetensors/mlx
   imports), falls back to the first `*.context_length` key in `model_info`.
"""

import argparse
import glob
import re
import sys

SETTINGS_MARKER = "scidesktop-nbi-settings-refresh"

DEFAULT_BUNDLE_GLOB = (
    "/opt/notebook-intelligence/lib/notebook_intelligence/labextension/static/*.js"
)

OLLAMA_MARKER = "scidesktop-nbi-ollama-context-fallback"

DEFAULT_OLLAMA_PROVIDER_GLOB = (
    "/opt/notebook-intelligence/lib/notebook_intelligence/"
    "llm_providers/ollama_llm_provider.py"
)

OLLAMA_ANCHOR = (
    '\n                        context_window = model_info[f"{model_family}.context_length"]\n'
)

OLLAMA_REPLACEMENT = (
    f"\n                        # {OLLAMA_MARKER}\n"
    '                        context_window = model_info.get(f"{model_family}.context_length")\n'
    "                        if context_window is None:\n"
    "                            context_window = next(\n"
    "                                (value for key, value in model_info.items()\n"
    '                                 if key.endswith(".context_length")),\n'
    "                                None,\n"
    "                            )\n"
    "                        if context_window is None:\n"
    '                            raise KeyError(f"{model_family}.context_length")\n'
)

COMMAND_PATTERN = re.compile(
    r'label:(?P<label>(?:\w+\.__\()?"Notebook Intelligence Settings"\)?),'
    r"execute:(?P<arg>\w+)=>\{"
    r'const (?P<tab>\w+)="string"==typeof\(null==(?P=arg)\?void 0:(?P=arg)\.tab\)'
    r'\?(?P=arg)\.tab:void 0;'
    r"(?P<widget>\w+)\.isDisposed&&\((?P=widget)=(?P<factory>\w+)\(\)\),"
    r"(?P=tab)&&(?P=widget)\.content\.selectTab\((?P=tab)\),"
    r'(?P=widget)\.isAttached\|\|(?P<app>\w+)\.shell\.add\((?P=widget),"main"\),'
    r"(?P=app)\.shell\.activateById\((?P=widget)\.id\)\}"
)

API_CLASS_PATTERN = re.compile(
    r"class (?P<api>\w+)\s*\{static async initialize\(\)\{"
    r"await this\.fetchCapabilities\(\)"
)


def patch_settings_bundle_text(text):
    if SETTINGS_MARKER in text:
        return text, False

    command_match = COMMAND_PATTERN.search(text)
    if command_match is None:
        return text, False

    api_match = API_CLASS_PATTERN.search(text)
    if api_match is None:
        raise ValueError(
            "found the settings command but not the NBI API class; "
            "refusing to apply a partial patch"
        )

    arg = command_match.group("arg")
    tab = command_match.group("tab")
    widget = command_match.group("widget")
    factory = command_match.group("factory")
    app = command_match.group("app")
    api = api_match.group("api")

    replacement = (
        f"label:{command_match.group('label')},"
        f"execute:async {arg}=>{{/*{SETTINGS_MARKER}*/"
        f'const {tab}="string"==typeof(null=={arg}?void 0:{arg}.tab)?{arg}.tab:void 0;'
        f"if(void 0!=={tab}){api}.__sdPendingTab={tab};"
        f"if({api}.__sdOpenInFlight)return {api}.__sdOpenInFlight;"
        f"return {api}.__sdOpenInFlight=(async()=>{{"
        f"try{{await {api}.fetchCapabilities()}}"
        f'catch(err){{{api}.__sdPendingTab=void 0;console.error("Notebook Intelligence: failed to refresh capabilities before opening settings",err);throw err;}}'
        f"const __sdTab={api}.__sdPendingTab;{api}.__sdPendingTab=void 0;"
        f"{widget}.isDisposed||{widget}.dispose();"
        f'{widget}={factory}(),__sdTab&&{widget}.content.selectTab(__sdTab),'
        f'{app}.shell.add({widget},"main"),'
        f"{app}.shell.activateById({widget}.id);"
        f"}})().finally(()=>{{{api}.__sdOpenInFlight=null;}})}}"
    )

    start, end = command_match.span()
    return text[:start] + replacement + text[end:], True


def apply_settings_bundle_patch(bundle_glob):
    bundle_files = sorted(glob.glob(bundle_glob))
    if not bundle_files:
        print(f"ERROR: no labextension bundles found under {bundle_glob}", file=sys.stderr)
        return False

    patched = 0
    already = 0
    for bundle_file in bundle_files:
        with open(bundle_file, encoding="utf-8") as fh:
            text = fh.read()
        if SETTINGS_MARKER in text:
            already += 1
            continue
        try:
            new_text, changed = patch_settings_bundle_text(text)
        except ValueError as exc:
            print(f"ERROR: {bundle_file}: {exc}", file=sys.stderr)
            return False
        if not changed:
            continue
        with open(bundle_file, "w", encoding="utf-8") as fh:
            fh.write(new_text)
        print(f"patched settings-open refresh into {bundle_file}")
        patched += 1

    if patched == 0 and already == 0:
        print(
            "ERROR: no bundle contained the Notebook Intelligence settings command anchor; "
            "update patch_nbi.py.",
            file=sys.stderr,
        )
        return False

    if already and not patched:
        print(f"settings-open refresh already patched ({already} bundle(s))")
    return True


def patch_ollama_provider_text(text):
    if OLLAMA_MARKER in text:
        return text, False

    if text.count(OLLAMA_ANCHOR) != 1:
        raise ValueError(
            "the Ollama context_length anchor no longer matches; update patch_nbi.py."
        )

    return text.replace(OLLAMA_ANCHOR, OLLAMA_REPLACEMENT, 1), True


def apply_ollama_provider_patch(provider_glob):
    provider_files = sorted(glob.glob(provider_glob))
    if not provider_files:
        print(f"ERROR: no Ollama provider module found under {provider_glob}", file=sys.stderr)
        return False

    for provider_file in provider_files:
        with open(provider_file, encoding="utf-8") as fh:
            text = fh.read()
        try:
            new_text, changed = patch_ollama_provider_text(text)
        except ValueError as exc:
            print(f"ERROR: {provider_file}: {exc}", file=sys.stderr)
            return False
        if not changed:
            print(f"Ollama context fallback already patched in {provider_file}")
            continue
        with open(provider_file, "w", encoding="utf-8") as fh:
            fh.write(new_text)
        print(f"patched Ollama context fallback into {provider_file}")
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundles", metavar="GLOB", default=None)
    parser.add_argument("--ollama", metavar="GLOB", default=None)
    args = parser.parse_args(argv)

    explicit = args.bundles is not None or args.ollama is not None
    ok = True
    if args.bundles is not None or not explicit:
        ok = apply_settings_bundle_patch(args.bundles or DEFAULT_BUNDLE_GLOB) and ok
    if args.ollama is not None or not explicit:
        ok = apply_ollama_provider_patch(args.ollama or DEFAULT_OLLAMA_PROVIDER_GLOB) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
