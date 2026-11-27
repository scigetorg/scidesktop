#!/usr/bin/env python3
"""Component tests for scidesktop_page_config.py page_config_hook."""
import json
import os
import pathlib
import sys
import tempfile
from types import SimpleNamespace

from jupyter_core.paths import jupyter_path
from jupyterlab_server.config import get_page_config

if "/opt/scidesktop/jupyter-env" not in sys.path:
    sys.path.insert(0, "/opt/scidesktop/jupyter-env")
import scidesktop_page_config

EXT = "@jupyterhub/jupyter-server-proxy"
ANNOUNCEMENTS = "@jupyterlab/apputils-extension:announcements"


def load_hook(prev_hook=None):
    settings = {}
    if prev_hook is not None:
        settings["page_config_hook"] = prev_hook
    app = SimpleNamespace(web_app=SimpleNamespace(settings=settings))
    scidesktop_page_config._load_jupyter_server_extension(app)
    return app.web_app.settings["page_config_hook"]


def _write_federated_ext(jdata, name, disabled_list):
    ext_dir = jdata / "labextensions" / name
    ext_dir.mkdir(parents=True, exist_ok=True)
    (ext_dir / "package.json").write_text(
        json.dumps(
            {
                "name": name,
                "version": "1.0.0",
                "jupyterlab": {
                    "_build": {"load": "static/remoteEntry.js"},
                    "disabledExtensions": disabled_list,
                },
            }
        ),
        encoding="utf-8",
    )


def run_case(
    hook,
    user_cfg,
    *,
    op_cfg=None,
    extra_setup=None,
    keep_env=False,
    symlink_user_to_op=False,
    federated_exts=None,
    source_ext_metadata=None,
    app_page_cfg=None,
    user_dropin_cfg=None,
):
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        home = root / "home"
        home.mkdir(parents=True)
        op = root / "op"
        if op_cfg is not None:
            (op / "labconfig").mkdir(parents=True)
            (op / "labconfig" / "page_config.json").write_text(
                json.dumps(op_cfg), encoding="utf-8"
            )

        if symlink_user_to_op:
            (home / ".jupyter").symlink_to(op)
            pc_file = op / "labconfig" / "page_config.json"
            orig = pc_file.read_text(encoding="utf-8")
        else:
            lc = home / ".jupyter" / "labconfig"
            lc.mkdir(parents=True)
            pc_file = lc / "page_config.json"
            orig = json.dumps(user_cfg) if user_cfg is not None else None
            if orig is not None:
                pc_file.write_text(orig, encoding="utf-8")
            if user_dropin_cfg is not None:
                dropin_dir = lc / "page_config.d"
                dropin_dir.mkdir(parents=True)
                (dropin_dir / "policy.json").write_text(
                    json.dumps(user_dropin_cfg), encoding="utf-8"
                )

        if extra_setup is not None:
            extra_setup(home)

        app_settings_dir = None
        if source_ext_metadata is not None or app_page_cfg is not None:
            app_dir = root / "app"
            (app_dir / "settings").mkdir(parents=True)
            (app_dir / "static").mkdir(parents=True)
            if source_ext_metadata is not None:
                (app_dir / "static" / "package.json").write_text(
                    json.dumps({"jupyterlab": {"extensionMetadata": source_ext_metadata}}),
                    encoding="utf-8",
                )
            if app_page_cfg is not None:
                (app_dir / "settings" / "page_config.json").write_text(
                    json.dumps(app_page_cfg),
                    encoding="utf-8",
                )
            app_settings_dir = str(app_dir / "settings")

        old_env = {
            k: os.environ.get(k)
            for k in (
                "HOME",
                "JUPYTER_CONFIG_DIR",
                "JUPYTER_CONFIG_PATH",
                "JUPYTER_PATH",
                "SCIDESKTOP_KEEP_DISABLED_SERVER_PROXY",
            )
        }
        try:
            os.environ["HOME"] = str(home)
            os.environ.pop("JUPYTER_CONFIG_DIR", None)
            if op_cfg is not None:
                os.environ["JUPYTER_CONFIG_PATH"] = str(op)
            else:
                os.environ.pop("JUPYTER_CONFIG_PATH", None)
            if federated_exts:
                jdata = root / "jdata"
                for name, disabled_list in federated_exts.items():
                    _write_federated_ext(jdata, name, disabled_list)
                os.environ["JUPYTER_PATH"] = str(jdata)
            else:
                os.environ.pop("JUPYTER_PATH", None)
            if keep_env:
                os.environ["SCIDESKTOP_KEEP_DISABLED_SERVER_PROXY"] = "1"
            else:
                os.environ.pop("SCIDESKTOP_KEEP_DISABLED_SERVER_PROXY", None)

            labext_paths = jupyter_path("labextensions")
            merged = get_page_config(labext_paths, app_settings_dir)
            handler = (
                SimpleNamespace(
                    extensionapp=SimpleNamespace(
                        app_settings_dir=app_settings_dir,
                        labextensions_path=labext_paths,
                        extra_labextensions_path=[],
                    )
                )
                if app_settings_dir is not None
                else None
            )
            res = hook(handler, merged)
            if orig is not None:
                assert pc_file.read_text(encoding="utf-8") == orig, "page_config.json mutated"
            return res
        finally:
            for k, v in old_env.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v


def main():
    hook = load_hook(prev_hook=lambda h, cfg: {**cfg, "hubUser": "alice"})

    # 1. Recent legacy Neurodesktop home (neurodeskSupporter) + chains after JupyterHub prev_hook.
    r1 = run_case(
        hook,
        {
            "disabledExtensions": {EXT: True, ANNOUNCEMENTS: True},
            "neurodeskSupporter": "false",
        },
    )
    assert r1["hubUser"] == "alice", r1
    assert EXT not in r1["disabledExtensions"], r1
    assert ANNOUNCEMENTS in r1["disabledExtensions"], r1

    # 2. Older legacy Neurodesktop home (~/neurodesktop-storage symlink).
    r2 = run_case(
        hook,
        {"disabledExtensions": {EXT: True}},
        extra_setup=lambda h: (h / "neurodesktop-storage").symlink_to("/tmp"),
    )
    assert EXT not in r2["disabledExtensions"], r2

    # 3. Older legacy Neurodesktop home (legacy ~/.bashrc marker).
    r3 = run_case(
        hook,
        {"disabledExtensions": {EXT: True}},
        extra_setup=lambda h: (h / ".bashrc").write_text(
            "# Neurodesk bashrc additions\n", encoding="utf-8"
        ),
    )
    assert EXT not in r3["disabledExtensions"], r3

    # 4. Opt-out via SCIDESKTOP_KEEP_DISABLED_SERVER_PROXY=1.
    r4 = run_case(
        hook,
        {"disabledExtensions": {EXT: True}, "neurodeskSupporter": "false"},
        keep_env=True,
    )
    assert EXT in r4["disabledExtensions"], r4

    # 5. Operator disabled + locked in JUPYTER_CONFIG_PATH on a legacy home must be preserved.
    r5 = run_case(
        hook,
        {"disabledExtensions": {EXT: True}, "neurodeskSupporter": "false"},
        op_cfg={"disabledExtensions": {EXT: True}, "lockedExtensions": {EXT: True}},
        extra_setup=lambda h: (h / "neurodesktop-storage").symlink_to("/tmp"),
    )
    assert EXT in r5["disabledExtensions"], r5
    assert EXT in r5["lockedExtensions"], r5

    # 6. Operator disabled (even unlocked) in JUPYTER_CONFIG_PATH on a legacy home must be preserved.
    r6 = run_case(
        hook,
        {"disabledExtensions": {EXT: True}, "neurodeskSupporter": "false"},
        op_cfg={"disabledExtensions": {EXT: True}},
    )
    assert EXT in r6["disabledExtensions"], r6

    # 7. Clean non-legacy home: deliberate user disable must be preserved.
    r7 = run_case(hook, {"disabledExtensions": {EXT: True}})
    assert EXT in r7["disabledExtensions"], r7

    # 8. FIFO at ~/.bashrc must not block.
    r8 = run_case(
        hook,
        {"disabledExtensions": {EXT: True}},
        extra_setup=lambda h: os.mkfifo(h / ".bashrc"),
    )
    assert EXT in r8["disabledExtensions"], r8

    # 9. ~/.jupyter symlinked to an operator config directory must preserve operator disable.
    r9 = run_case(
        hook,
        None,
        op_cfg={"disabledExtensions": {EXT: True}},
        extra_setup=lambda h: (h / "neurodesktop-storage").symlink_to("/tmp"),
        symlink_user_to_op=True,
    )
    assert EXT in r9["disabledExtensions"], r9

    # 10. Installed federated extension metadata disabling server-proxy must be preserved.
    r10 = run_case(
        hook,
        {"disabledExtensions": {EXT: True}, "neurodeskSupporter": "false"},
        federated_exts={"org-policy-ext": [EXT]},
    )
    assert EXT in r10["disabledExtensions"], r10

    # 11. Extension A disables server-proxy while Extension B disables A via metadata:
    # JupyterLab still applies A's policy (A is not disabled in static config), so preserve.
    r11 = run_case(
        hook,
        {"disabledExtensions": {EXT: True}, "neurodeskSupporter": "false"},
        federated_exts={"ext-a": [EXT], "ext-b": ["ext-a"]},
    )
    assert EXT in r11["disabledExtensions"], r11

    # 12. Federated metadata for ext-a supersedes source extensionMetadata for ext-a:
    # ext-a's federated metadata does not disable server-proxy, so legacy user disable recovers.
    r12 = run_case(
        hook,
        {"disabledExtensions": {EXT: True}, "neurodeskSupporter": "false"},
        federated_exts={"ext-a": ["some-other-ext"]},
        source_ext_metadata={"ext-a": {"disabledExtensions": [EXT]}},
    )
    assert EXT not in r12["disabledExtensions"], r12

    # 13. App-level page_config.json mapping disabledExtensions[EXT]=False is treated
    # as disabled by jupyterlab_server 2.28.1; preserve that app-level disable.
    r13 = run_case(
        hook,
        {"disabledExtensions": {EXT: True}, "neurodeskSupporter": "false"},
        app_page_cfg={"disabledExtensions": {EXT: False}},
    )
    assert EXT in r13["disabledExtensions"], r13

    # 14. User page_config.d drop-in alone disabling server-proxy on a legacy home must be preserved.
    r14 = run_case(
        hook,
        None,
        extra_setup=lambda h: (h / "neurodesktop-storage").symlink_to("/tmp"),
        user_dropin_cfg={"disabledExtensions": {EXT: True}},
    )
    assert EXT in r14["disabledExtensions"], r14

    # 15. User page_config.d drop-in AND legacy page_config.json both disabling server-proxy:
    # drop-in must still keep server-proxy disabled after subtracting legacy page_config.json.
    r15 = run_case(
        hook,
        {"disabledExtensions": {EXT: True}, "neurodeskSupporter": "false"},
        user_dropin_cfg={"disabledExtensions": {EXT: True}},
    )
    assert EXT in r15["disabledExtensions"], r15

    print("PAGE_CONFIG_HOOK_TESTS_OK")


if __name__ == "__main__":
    main()
