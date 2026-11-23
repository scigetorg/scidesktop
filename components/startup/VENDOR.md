# Vendored from jupyter/docker-stacks

Source: https://github.com/jupyter/docker-stacks
Commit: 660dc22b671e02e765273c9f8931588b4a00f263 (2026-11-10)
Licence: BSD-3-Clause, see docker-stacks/LICENSE.md

Files in `docker-stacks/` are copied unchanged from:

- `images/docker-stacks-foundation/`: `_docker_stacks_log.sh`, `start.sh`,
  `run-hooks.sh`, `fix-permissions`
- `images/base-notebook/`: `start-notebook.py`, `start-notebook.sh`,
  `start-singleuser.py`, `start-singleuser.sh`, `docker_healthcheck.py`,
  `jupyter_server_config.py`

Not vendored: `10activate-conda-env.sh`. The image ships its own
`before-notebook.d` hook instead (each component's `rootfs/`).

Local changes, if any, are made in separate commits after the unchanged copy
so `git log -p components/startup/docker-stacks` shows each one:

- `start.sh`: replaced `sudo` privilege-drop and `GRANT_SUDO` with
  `setpriv --no-new-privs --inh-caps -all [--bounding-set -all]` so the OS
  layer does not ship SUID `sudo`.

To update: copy the same files from a newer commit, update the commit above,
and run `docker buildx bake startup-test` and the smoke test.
