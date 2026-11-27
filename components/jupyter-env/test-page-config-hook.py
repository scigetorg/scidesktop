#!/usr/bin/env python3
"""Component tests for jupyter_server_config.d/jupyter-env.py page_config_hook."""
import json
import os
import pathlib
import tempfile

from jupyter_core.paths import jupyter_path
from jupyter_server.serverapp import ServerApp
from jupyterlab_server.config import get_page_config

EXT = "@jupyterhub/jupyter-server-proxy"
ANNOUNCEMENTS = "@jupyterlab/apputils-extension:announcements"


def load_hook():
    app = ServerApp()
    app.load_config_file()
    return app.config.ServerApp.tornado_settings.get_value({})["page_config_hook"]


def run_case(
    hook,
    user_cfg,
    *,
    op_cfg=None,
    extra_setup=None,
    keep_env=False,
    symlink_user_to_op=False,
    ext_disables_proxy=False,
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
            if ext_disables_proxy:
                jdata = root / "jdata"
                ext_dir = jdata / "labextensions" / "org-policy-ext"
                ext_dir.mkdir(parents=True)
                (ext_dir / "package.json").write_text(
                    json.dumps(
                        {
                            "name": "org-policy-ext",
                            "version": "1.0.0",
                            "jupyterlab": {
                                "_build": {"load": "static/remoteEntry.js"},
                                "disabledExtensions": [EXT],
                            },
                        }
                    ),
                    encoding="utf-8",
                )
                os.environ["JUPYTER_PATH"] = str(jdata)
            else:
                os.environ.pop("JUPYTER_PATH", None)
            if keep_env:
                os.environ["SCIDESKTOP_KEEP_DISABLED_SERVER_PROXY"] = "1"
            else:
                os.environ.pop("SCIDESKTOP_KEEP_DISABLED_SERVER_PROXY", None)

            merged = get_page_config(jupyter_path("labextensions"), None)
            res = hook(None, merged)
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
        ext_disables_proxy=True,
    )
    assert EXT in r10["disabledExtensions"], r10

    print("PAGE_CONFIG_HOOK_TESTS_OK")


if __name__ == "__main__":
    main()
