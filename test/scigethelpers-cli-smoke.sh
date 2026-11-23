#!/bin/bash
# End-to-end check of an image that copies the scigethelpers-cli component.
#
#   ./test/scigethelpers-cli-smoke.sh [image]
#
# Runs what a terminal runs: a login shell of the notebook user in a started
# session, with the session's Slurm queue up.

set -uo pipefail

IMAGE="${1:-neurodesktop}"
NAME="scigethelpers-cli-smoke-$$"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() { docker rm -f "${NAME}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

terminal() { docker exec -u jovyan -w /tmp "${NAME}" bash -lc "$1" 2>&1; }

echo "scigethelpers-cli smoke: ${IMAGE}"
docker run -d --name "${NAME}" --cpus=2 --memory=2g -e JUPYTER_TOKEN=scigethelpers-cli-smoke "${IMAGE}" >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }
for _ in $(seq 1 120); do
    docker exec "${NAME}" curl -fsS -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null && break
    sleep 1
done
terminal '/opt/slurm/bin/slurm-session wait' >/dev/null

help="$(terminal 'scigethelpers --help')"
grep -q '^usage: scigethelpers <command>' <<<"${help}" && grep -q '^  cite ' <<<"${help}" && grep -q '^  kernel ' <<<"${help}" \
    && pass "scigethelpers --help lists the commands" || fail "scigethelpers --help lists the commands"
[ "$(terminal 'scigethelpers check slurm')" = "[PASS] slurm  partitions: scidesktop*" ] \
    && pass "scigethelpers check slurm finds the session's queue" \
    || fail "scigethelpers check slurm finds the session's queue (got: $(terminal 'scigethelpers check slurm'))"
[ "$(terminal 'scigethelpers check gpu')" = "[SKIP] gpu    no NVIDIA GPU visible in this container" ] \
    && pass "scigethelpers check gpu skips without a GPU" || fail "scigethelpers check gpu skips without a GPU"
info="$(terminal 'scigethelpers info')"
grep -q '^Image: .*scigethelpers-cli.*slurm' <<<"${info}" && grep -qE '^CPUs: +2$' <<<"${info}" \
    && grep -qE '^Memory: +2\.0 GiB$' <<<"${info}" \
    && pass "scigethelpers info shows the components and the container's 2 CPUs and 2 GiB" \
    || { fail "scigethelpers info shows the components and the container's 2 CPUs and 2 GiB"; printf '%s\n' "${info}" | sed 's/^/        /'; }
[ "$(terminal 'scigethelpers kernel list')" = "No container kernels registered. Add one with: scigethelpers kernel add <module>" ] \
    && pass "scigethelpers kernel list answers" || fail "scigethelpers kernel list answers"

# A module loaded in a terminal is recorded, and scigethelpers cite reads the
# record. The catalogue is a local file: this check needs no network.
out="$(terminal '
    modules="${HOME}/.local/share/sciget/modules/smokecat/smoketool"
    mkdir -p "${modules}" && echo "whatis(\"smoke\")" > "${modules}/1.2.lua"
    echo "package=${LMOD_PACKAGE_PATH:-}"
    module use "${HOME}/.local/share/sciget/modules/smokecat" && module load smoketool/1.2
    cut -f 1,2 "${HOME}/.local/state/scigethelpers/module-usage.tsv" | tr "\t" "/"
    echo "{\"smoketool\": {\"apps\": {\"smoketool 1.2\": {\"version\": \"20260101\", \"exec\": \"\", \"image\": \"smoketool_1.2\"}}, \"categories\": [\"programming\"], \"citation\": \"Smoke, A. (2026). https://doi.org/10.0000/smoke\"}}" > /tmp/apps.json
    SCIGETHELPERS_CITE_CATALOGUE_URL=file:///tmp/apps.json scigethelpers cite >/dev/null && grep -c "doi.org/10.0000/smoke" "${HOME}/CITATIONS.md"')"
[ "${out}" = "$(printf 'package=/opt/scigethelpers-cli/lmod\nsmoketool/1.2\n1')" ] \
    && pass "a loaded module is recorded and scigethelpers cite writes its citation" \
    || { fail "a loaded module is recorded and scigethelpers cite writes its citation"; printf '%s\n' "${out}" | sed 's/^/        /'; }

# Full end-to-end scigethelpers uv kernel lifecycle: init (including space in
# folder name), execute a cell on the registered kernel via jupyter_client,
# move the folder, offline rebuild, re-execute, and remove.
uv_out="$(docker exec -i -u jovyan -w /tmp "${NAME}" /opt/conda/bin/python - <<'PY' 2>&1
import json
import os
import subprocess
import tempfile
from pathlib import Path
from jupyter_client import KernelManager
from jupyter_client.kernelspec import KernelSpecManager

with tempfile.TemporaryDirectory() as td:
    tmp = Path(td)
    project = tmp / "analysis uv"
    project.mkdir()
    data_dir = tmp / "jupyter"
    env = dict(
        os.environ,
        JUPYTER_DATA_DIR=str(data_dir),
        UV_CACHE_DIR=str(tmp / "uv-cache"),
        UV_PYTHON="/opt/conda/bin/python",
        UV_PYTHON_DOWNLOADS="never",
    )
    env.pop("UV_OFFLINE", None)

    def run_uv(action, folder, extra_env=None):
        e = dict(env, **(extra_env or {}))
        r = subprocess.run(["scigethelpers", "uv", action, str(folder)], env=e, capture_output=True, text=True, timeout=300)
        assert r.returncode == 0, f"scigethelpers uv {action} failed:\n{r.stdout}\n{r.stderr}"

    run_uv("init", project)
    specs = list((data_dir / "kernels").glob("*/kernel.json"))
    assert len(specs) == 1, specs
    kernel_name = specs[0].parent.name

    def exec_on_kernel(kname, folder):
        km = KernelManager(
            kernel_name=kname,
            kernel_spec_manager=KernelSpecManager(kernel_dirs=[str(data_dir / "kernels")]),
        )
        km.start_kernel(cwd=str(folder), env=dict(os.environ, CONDA_PREFIX="/other-env", PYTHONPATH="/missing"))
        try:
            kc = km.blocking_client()
            kc.start_channels()
            try:
                kc.wait_for_ready(timeout=60)
                code = (
                    "import os, sys\n"
                    f"assert sys.prefix == {str(folder / '.venv')!r}, sys.prefix\n"
                    "assert 'CONDA_PREFIX' not in os.environ\n"
                    "assert 'PYTHONPATH' not in os.environ\n"
                    "print('UV_KERNEL_OK')\n"
                )
                msg_id = kc.execute(code)
                out = []
                while True:
                    msg = kc.get_iopub_msg(timeout=30)
                    if msg.get("parent_header", {}).get("msg_id") != msg_id:
                        continue
                    if msg["msg_type"] == "stream":
                        out.append(msg["content"]["text"])
                    elif msg["msg_type"] == "error":
                        raise AssertionError(msg["content"])
                    elif msg["msg_type"] == "status" and msg["content"]["execution_state"] == "idle":
                        break
                assert "UV_KERNEL_OK" in "".join(out), out
            finally:
                kc.stop_channels()
        finally:
            km.shutdown_kernel(now=True)

    exec_on_kernel(kernel_name, project)

    # Move the project, rebuild offline, re-execute, and cleanly remove.
    moved = tmp / "renamed analysis"
    project.rename(moved)
    run_uv("rebuild", moved, {"UV_OFFLINE": "1"})
    specs2 = list((data_dir / "kernels").glob("*/kernel.json"))
    moved_spec = [s for s in specs2 if json.loads(s.read_text())["metadata"]["scigethelpers_uv"]["project"] == str(moved)]
    assert len(moved_spec) == 1, specs2
    exec_on_kernel(moved_spec[0].parent.name, moved)

    # Verify atomic rollback if kernelspec publication fails after venv rebuild.
    sentinel = moved / ".venv" / "rollback_sentinel.txt"
    sentinel.write_text("keep-me")
    spec_dir = moved_spec[0].parent
    os.chmod(spec_dir, 0o500)
    try:
        r_fail = subprocess.run(
            ["scigethelpers", "uv", "rebuild", str(moved)],
            env=dict(env, UV_OFFLINE="1"),
            capture_output=True,
            text=True,
            timeout=300,
        )
        assert r_fail.returncode != 0, f"expected kernelspec publication failure: {r_fail.stdout}"
        assert sentinel.read_text() == "keep-me", "rebuild did not roll back .venv on kernelspec failure"
        assert not list(moved.glob(".venv.scigethelpers_uv-backup-*"))
    finally:
        os.chmod(spec_dir, 0o700)

    run_uv("remove", moved)
    assert not moved_spec[0].parent.exists()
    print("UV_LIFECYCLE_OK")
PY
)"
if grep -qx 'UV_LIFECYCLE_OK' <<<"${uv_out}"; then
    pass "scigethelpers uv init, kernel execution, move+offline rebuild, and remove passed"
else
    fail "scigethelpers uv init, kernel execution, move+offline rebuild, and remove passed"
    printf '%s\n' "${uv_out}" | tail -n 15 | sed 's/^/        /'
fi

echo
echo "  NOT TESTED: scigethelpers kernel add WITH A REAL TOOL CONTAINER. THAT NEEDS A"
echo "  CONTAINER WITH ipykernel. The command's refusal of a module that is not a"
echo "  container's is checked by the component's test."
echo
if [ "${FAILED}" -eq 0 ]; then
    echo "scigethelpers-cli smoke: all checks passed"
else
    echo "scigethelpers-cli smoke: ${FAILED} check(s) failed"
fi
exit "${FAILED}"
