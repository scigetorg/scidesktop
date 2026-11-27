#!/usr/bin/env python3
"""Component tests for jupyter_server_config.d/jupyter-env.py page_config_hook."""
import json
import os
import pathlib
import tempfile
from types import SimpleNamespace

from jupyter_core.paths import jupyter_path
from jupyter_server.serverapp import ServerApp
from jupyterlab_server.config import get_page_config

EXT = "@jupyterhub/jupyter-server-proxy"
ANNOUNCEMENTS = "@jupyterlab/apputils-extension:announcements"


def load_hook():
    app = ServerApp()
    app.load_config_file()
    return app.config.ServerApp.tornado_settings.get_value({})["page_config_hook"]


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
            orig = json.dumps(user_cfg)
            pc_file.write_text(orig, encoding="utf-8")

        if extra_setup is not None:
            extra_setup(home)

        app_settings_dir = None
        if source_ext_metadata is not None:
            app_dir = root / "app"
            (app_dir / "settings").mkdir(parents=True)
            (app_dir / "static").mkdir(parents=True)
            (app_dir / "static" / "package.json").write_text(
                json.dumps({"jupyterlab": {"extensionMetadata": source_ext_metadata}}),
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
            assert pc_file.read_text(encoding="utf-8") == orig, "page_config.json mutated"
            return res
        finally:
            for k, v in old_env.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v


def main():
    hook = load_hook()

    # 1. Recent legacy Neurodesktop home (neurodeskSupporter in user page_config.json).
    r1 = run_case(
        hook,
        {
            "disabledExtensions": {EXT: True, ANNOUNCEMENTS: True},
            "neurodeskSupporter": "false",
        },
    )
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

    print("PAGE_CONFIG_HOOK_TESTS_OK")


if __name__ == "__main__":
    main()
