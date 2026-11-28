#!/bin/bash
# The component's own test: runs on the OS layer as the notebook user, with
# Lmod, the Slurm component and the Jupyter environment's Python.
set -euo pipefail
HOME="$(mktemp -d)"
export HOME
cd "${HOME}"
supervisor=""
# Says where a check failed: the checks themselves print nothing.
trap 'echo "scigethelpers-cli test: the check at line ${LINENO} failed" >&2' ERR
trap '[ -z "${supervisor}" ] || kill "${supervisor}" 2>/dev/null || true' EXIT

# The command lists what this image has, and nothing it does not.
help="$(scigethelpers --help)"
for command in cite kernel uv check info "agent preflight"; do
    grep -q "^  ${command} " <<<"${help}"
done
if grep -E '^  (jobs|update|test|t3|astra|lightcone)' <<<"${help}"; then
    echo "scigethelpers --help lists a command this image does not have" >&2
    exit 1
fi
grep -q "scigethelpers-uv" <<<"${help}"
[ "$(scigethelpers help check)" = "$(scigethelpers check --help)" ]
[ "$(scigethelpers help agent preflight)" = "$(scigethelpers agent preflight --help)" ]
if scigethelpers inf 2>"${HOME}/error"; then exit 1; fi
grep -q "Did you mean 'info'?" "${HOME}/error"
if scigethelpers agent 2>"${HOME}/error"; then exit 1; fi
grep -q "scigethelpers agent preflight" "${HOME}/error"
scigethelpers --version | grep -q '^scigethelpers {cli_sha256: [0-9a-f]\{64\}}$'
[ "$(readlink -f "$(command -v scigethelpers-kernel)")" = /opt/scigethelpers-cli/lib/scigethelpers_kernel.py ]
[ "$(readlink -f "$(command -v scigethelpers-uv)")" = /opt/scigethelpers-cli/lib/scigethelpers_uv.py ]

# check: Slurm is not running yet, no CVMFS repo configured here, no GPU, no T3.
[ "$(scigethelpers check gpu)" = "[SKIP] gpu    no NVIDIA GPU visible in this container" ]
scigethelpers check cvmfs | grep -q '^\[SKIP\] cvmfs'
scigethelpers check t3 | grep -q '^\[SKIP\] t3'
if SCIDESKTOP_CVMFS_REPOSITORIES=neurodesk.ardc.edu.au scigethelpers check cvmfs >"${HOME}/cvmfs"; then exit 1; fi
grep -q '^\[FAIL\] cvmfs  neurodesk\.ardc\.edu\.au:' "${HOME}/cvmfs"
# Multiple configured repos are each reported, deduplicated, and invalid names ignored.
if SCIDESKTOP_CVMFS_REPOSITORIES="neurodesk.ardc.edu.au,software.eessi.io,neurodesk.ardc.edu.au,../bad" \
        scigethelpers check cvmfs >"${HOME}/cvmfs-multi"; then exit 1; fi
[ "$(wc -l < "${HOME}/cvmfs-multi")" -eq 2 ]
grep -q '^\[FAIL\] cvmfs  neurodesk\.ardc\.edu\.au:' "${HOME}/cvmfs-multi"
grep -q '^\[FAIL\] cvmfs  software\.eessi\.io:' "${HOME}/cvmfs-multi"
SCIDESKTOP_CVMFS_MODE=disabled SCIDESKTOP_CVMFS_REPOSITORIES=neurodesk.ardc.edu.au scigethelpers check cvmfs | grep -q '^\[SKIP\] cvmfs'
if scigethelpers check slurm >"${HOME}/slurm"; then exit 1; fi
grep -q '^\[FAIL\] slurm' "${HOME}/slurm"
# check --json produces structured output and preserves exit status.
check_json="$(scigethelpers check --json gpu t3)"
/opt/conda/bin/python3 -c 'import json, sys; d = json.loads(sys.argv[1]); assert d["ok"] is True; assert [c["name"] for c in d["checks"]] == ["gpu", "t3"]; assert all(c["status"] == "SKIP" for c in d["checks"])' "${check_json}"

# With the session's queue, the check passes and names its partition. The
# queue gets ports of this test's own: on some builders the tests of several
# components run at once and share one network.
controller_port="$(shuf -i 20000-39999 -n 1)"
export SCIDESKTOP_SLURM_PORTS="${controller_port},$(( controller_port + 20000 ))"
/opt/slurm/bin/slurm-session run >"${HOME}/slurm-session.log" 2>&1 &
supervisor=$!
/opt/slurm/bin/slurm-session wait
checked="$(scigethelpers check slurm)" || true
[ "${checked}" = "[PASS] slurm  partitions: scidesktop*" ] || { echo "scigethelpers check slurm: ${checked}" >&2; false; }

# agent preflight: human-readable and --json output with live Slurm and Lmod.
preflight="$(scigethelpers agent preflight)"
grep -q 'Agent guidance (user defaults):' <<<"${preflight}"
grep -q 'Slurm configured node capacity' <<<"${preflight}"
grep -q 'scidesktop\*' <<<"${preflight}"
preflight_json="$(scigethelpers agent preflight --json --cwd "${HOME}")"
/opt/conda/bin/python3 - "${preflight_json}" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data["lmod"]["available"] is True
assert data["slurm_capacity"]["available"] is True
assert any(p["partition"].startswith("scidesktop") for p in data["slurm_capacity"]["partitions"])
assert data["checks_ok"] is True
assert len(data["user_guidance"]) == 3
PY

kill -TERM "${supervisor}"; wait "${supervisor}"; supervisor=""

# info names the image's components and the container's resources, and supports --json / --no-probes.
info="$(scigethelpers info)"
grep -q '^Image: .*scigethelpers-cli' <<<"${info}"
grep -qE '^CPUs: +[0-9.]+$' <<<"${info}"
grep -qE '^Memory: +[0-9.]+ GiB$' <<<"${info}"
grep -qE '^GPU: +none visible$' <<<"${info}"
info_json="$(scigethelpers info --json)"
/opt/conda/bin/python3 -c 'import json, sys; d = json.loads(sys.argv[1]); assert "scigethelpers-cli" in d["components"]; assert d["gpu"]["probed"] is True; assert d["cvmfs"]["probed"] is True' "${info_json}"
info_fast="$(scigethelpers info --no-probes --json)"
/opt/conda/bin/python3 -c 'import json, sys; d = json.loads(sys.argv[1]); assert d["gpu"]["probed"] is False; assert d["cvmfs"]["probed"] is False' "${info_fast}"

# cite: Lmod's site package records a loaded sciget module, and the command
# turns the record into citations from a catalogue (a local one here: a build
# has no business on the network).
. /usr/local/bin/before-notebook.d/46-scigethelpers-cli.sh
[ "${LMOD_PACKAGE_PATH}" = /opt/scigethelpers-cli/lmod ]
cite_empty="$(scigethelpers cite --status --json)"
/opt/conda/bin/python3 -c 'import json, sys; d = json.loads(sys.argv[1]); assert d["load_count"] == 0 and d["citations_exists"] is False' "${cite_empty}"
modules="${HOME}/.local/share/sciget/modules/microscopy"
mkdir -p "${modules}/smoketool" "${HOME}/other/othertool"
echo 'whatis("smoke")' > "${modules}/smoketool/1.2.lua"
echo 'whatis("other")' > "${HOME}/other/othertool/1.0.lua"
bash -lc "module use '${modules}' '${HOME}/other' && module load smoketool/1.2 othertool/1.0" >/dev/null 2>&1
log="${HOME}/.local/state/scigethelpers/module-usage.tsv"
[ "$(cut -f 1,2 "${log}")" = "$(printf 'smoketool\t1.2')" ]
cat > "${HOME}/apps.json" <<'JSON'
{"smoketool": {"apps": {"smoketool 1.2": {"version": "20260101", "exec": "", "image": "smoketool_1.2"}},
               "categories": ["programming"], "citation": "Smoke, A. (2026). A tool. https://doi.org/10.0000/smoke"}}
JSON
cite_out="$(SCIGETHELPERS_CITE_CATALOGUE_URL="file://${HOME}/apps.json" scigethelpers cite --json)"
/opt/conda/bin/python3 -c 'import json, sys; d = json.loads(sys.argv[1]); assert d["ok"] is True and d["tool_count"] == 1 and d["load_count"] == 1' "${cite_out}"
grep -q 'smoketool (v1.2, built 2026-01-01) was run in Neurodesk/Scidesktop (Renton et al., 2024).' "${HOME}/CITATIONS.md"
grep -q 'https://doi.org/10.0000/smoke' "${HOME}/CITATIONS.md"
# Atomic --no-clobber refuses to overwrite an existing CITATIONS.md.
printf 'user-edits\n' > "${HOME}/CITATIONS-keep.md"
if cite_nc="$(SCIGETHELPERS_CITE_CATALOGUE_URL="file://${HOME}/apps.json" scigethelpers cite --no-clobber --json --output "${HOME}/CITATIONS-keep.md")"; then exit 1; fi
/opt/conda/bin/python3 -c 'import json, sys; d = json.loads(sys.argv[1]); assert d["ok"] is False and d["needs_overwrite"] is True' "${cite_nc}"
[ "$(cat "${HOME}/CITATIONS-keep.md")" = "user-edits" ]
cite_status="$(scigethelpers cite --status --json)"
/opt/conda/bin/python3 -c 'import json, sys; d = json.loads(sys.argv[1]); assert d["load_count"] == 1 and d["citations_exists"] is True and len(d["unique_tools"]) == 1' "${cite_status}"
# Also verify catalogs.json entries pointing at domains.json with a domain selector.
mkdir -p "${HOME}/.config/sciget"
cat > "${HOME}/domains.json" <<JSON
{"schemaVersion": 1, "domains": {"microscopy": {"appJsonUrl": "file://${HOME}/apps.json"}}}
JSON
cat > "${HOME}/.config/sciget/catalogs.json" <<JSON
[{"name": "microscopy", "url": "file://${HOME}/domains.json", "domain": "microscopy", "use": true}]
JSON
scigethelpers cite --output "${HOME}/CITATIONS-domains.md" >/dev/null
grep -q 'smoketool (v1.2, built 2026-01-01) was run in Neurodesk/Scidesktop (Renton et al., 2024).' "${HOME}/CITATIONS-domains.md"
grep -q 'https://doi.org/10.0000/smoke' "${HOME}/CITATIONS-domains.md"

# kernel: no container kernel yet, JSON list works, and an invalid module is
# refused with a reason, without a traceback.
scigethelpers kernel list | grep -q '^No container kernels registered'
kernel_json="$(scigethelpers kernel list --json)"
/opt/conda/bin/python3 -c 'import json, sys; assert json.loads(sys.argv[1]) == {"kernels": []}' "${kernel_json}"
if scigethelpers kernel add nosuchtool/1.0 2>"${HOME}/error"; then exit 1; fi
grep -q "scigethelpers-kernel: error: could not load module 'nosuchtool/1.0'" "${HOME}/error"
if grep -q Traceback "${HOME}/error"; then exit 1; fi

# uv: list, offline refusal checks, and atomic rebuild rollback on failure.
scigethelpers uv list | grep -q '^No uv kernels registered'
uv_json="$(scigethelpers uv list --json)"
/opt/conda/bin/python3 -c 'import json, sys; assert json.loads(sys.argv[1]) == {"kernels": []}' "${uv_json}"
if scigethelpers uv init "${HOME}" 2>"${HOME}/error"; then exit 1; fi
grep -q "Choose an analysis subfolder" "${HOME}/error"
if scigethelpers uv init "${HOME}/does-not-exist" 2>"${HOME}/error"; then exit 1; fi
grep -q "Create the analysis folder first" "${HOME}/error"
uvproj="${HOME}/uv-rollback-proj"
mkdir -p "${uvproj}/.venv/bin"
printf 'uv = 0.13.9\n' > "${uvproj}/.venv/pyvenv.cfg"
printf 'sentinel\n' > "${uvproj}/.venv/sentinel.txt"
printf '{"project": "%s"}\n' "${uvproj}" > "${uvproj}/.scigethelpers_uv.json"
printf '[project]\nname = "demo"\nversion = "0.1.0"\n' > "${uvproj}/pyproject.toml"
printf 'not-a-valid-lock\n' > "${uvproj}/uv.lock"
if scigethelpers uv rebuild "${uvproj}" 2>"${HOME}/error"; then exit 1; fi
[ "$(cat "${uvproj}/.venv/sentinel.txt")" = "sentinel" ]
# Failed first init must clean up the partial .venv so retrying is not refused as unmanaged.
uvretry="${HOME}/uv-retry-proj"
mkdir -p "${uvretry}"
if UV_OFFLINE=1 scigethelpers uv init "${uvretry}" 2>"${HOME}/error"; then exit 1; fi
test ! -e "${uvretry}/.venv"
if UV_OFFLINE=1 scigethelpers uv init "${uvretry}" 2>"${HOME}/error"; then exit 1; fi
if grep -q "unmanaged" "${HOME}/error"; then exit 1; fi
pw_home="$(getent passwd "$(id -un)" | cut -d: -f6)"
if [ -n "${pw_home}" ] && HOME="" scigethelpers uv init "${pw_home}" 2>"${HOME}/error"; then exit 1; fi
if [ -n "${pw_home}" ]; then grep -q "Choose an analysis subfolder" "${HOME}/error"; fi
if scigethelpers uv remove "${uvproj}" 2>"${HOME}/error"; then exit 1; fi
grep -q "No uv kernel registration" "${HOME}/error"

# Unit checks for command dispatch and probe behavior.
/opt/conda/bin/python3 - <<'PY'
import importlib.util, os, signal, subprocess, sys, time
from pathlib import Path
from unittest import mock

spec = importlib.util.spec_from_file_location("scigethelpers_cli", "/opt/scigethelpers-cli/lib/scigethelpers_cli.py")
cli = importlib.util.module_from_spec(spec)
sys.modules["scigethelpers_cli"] = cli
spec.loader.exec_module(cli)

# Registering a built-in is sufficient to route its arguments and return status.
inspect = mock.Mock(return_value=23)
entry = cli.Command(("inspect", "session"), "Environment", "Inspect this session", inspect)
with mock.patch.object(cli, "COMMANDS", (*cli.COMMANDS, entry)):
    assert cli.main(["inspect", "session", "--label", "two words"]) == 23
inspect.assert_called_once_with(["--label", "two words"])

# 1. An ordinary non-CVMFS mount (/proc/sys) must not pass as CVMFS.
orig_root = cli.CVMFS_ROOT
try:
    cli.CVMFS_ROOT = Path("/proc")
    res = cli.probe_cvmfs("sys", timeout=5)
    assert not res.ok and "not a CVMFS mount" in res.error, res
finally:
    cli.CVMFS_ROOT = orig_root

# 2. Queued CVMFS probes (>8 repos) must not overrun a shared deadline.
def slow_probe(repo, timeout=60):
    time.sleep(min(timeout, 0.35))
    return cli.CvmfsProbeResult(repo=repo, ok=False, error="slow")

with mock.patch.object(cli, "probe_cvmfs", side_effect=slow_probe):
    t0 = time.monotonic()
    out = cli.probe_cvmfs_repos([f"repo{i}.example.org" for i in range(12)], timeout=0.3)
    elapsed = time.monotonic() - t0
    assert len(out) == 12 and elapsed < 0.75, f"deadline overrun: {elapsed:.2f}s"

# 3. collect_info(run_probes=False) must never scan /cvmfs directory fallback.
with mock.patch.object(cli, "_repos_from_cvmfs_dir", side_effect=AssertionError("must not scan /cvmfs")):
    info = cli.collect_info(run_probes=False)
    assert info["cvmfs"]["probed"] is False

# 4. SIGTERM to the CLI cleans up detached child probe process groups.
marker = f"scigethelpers-sigterm-test-{os.getpid()}"
parent = subprocess.Popen(
    [
        sys.executable, "-c",
        f"import importlib.util, signal, sys; "
        f"spec = importlib.util.spec_from_file_location('m', '/opt/scigethelpers-cli/lib/scigethelpers_cli.py'); "
        f"m = importlib.util.module_from_spec(spec); sys.modules['m'] = m; spec.loader.exec_module(m); "
        f"signal.signal(signal.SIGTERM, m._handle_termination); "
        f"m.run(['/bin/bash', '-c', 'exec -a {marker} sleep 30'], 30)",
    ],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
)
child_pid = None
for _ in range(50):
    for p in Path("/proc").iterdir():
        if p.name.isdigit():
            try:
                if marker.encode() in (p / "cmdline").read_bytes():
                    child_pid = int(p.name)
                    break
            except OSError:
                pass
    if child_pid is not None:
        break
    time.sleep(0.05)
assert child_pid is not None, "test child probe did not start"
parent.terminate()
parent.wait(timeout=5)
time.sleep(0.2)
assert not Path(f"/proc/{child_pid}").exists(), f"detached probe pid {child_pid} survived SIGTERM"
# 5. Compute-only GPU (failing vgl-eglinfo) stays PASS even when X11 display is reachable.
def fake_which(name):
    return f"/usr/local/bin/{name}" if name in ("vgl-eglinfo", "vglrun", "glxinfo") else None

def fake_run(argv, timeout, env=None):
    if argv[0].endswith("vgl-eglinfo"):
        return subprocess.CompletedProcess(list(argv), 1, "", "EGL_NOT_INITIALIZED")
    raise AssertionError(f"GLX should not run after failed EGL probe: {argv}")

with (
    mock.patch.object(cli.shutil, "which", side_effect=fake_which),
    mock.patch.object(cli, "resolve_vgl_display", return_value="egl"),
    mock.patch.object(cli, "_x11_display_reachable", return_value=True),
    mock.patch.object(cli, "run", side_effect=fake_run),
):
    gpu_res = cli._gpu_result_from_probe("ok", ["GPU 0: NVIDIA L4"], "")
    assert len(gpu_res) == 1 and gpu_res[0].status == "PASS" and "compute available" in gpu_res[0].detail, gpu_res
PY

# Bash completion: stays in sync with --help and check --help, and prints no output on source.
comp_out="$(bash -ic '. /etc/bash.bashrc.d/scigethelpers-cli.sh; COMP_WORDS=(scigethelpers ""); COMP_CWORD=1; _scigethelpers_complete; printf "%s\n" "${COMPREPLY[@]}"' 2>/dev/null)"
for word in cite kernel uv check info agent help; do
    grep -qx "${word}" <<<"${comp_out}"
done
check_comp="$(bash -ic '. /etc/bash.bashrc.d/scigethelpers-cli.sh; COMP_WORDS=(scigethelpers check ""); COMP_CWORD=2; _scigethelpers_complete; printf "%s\n" "${COMPREPLY[@]}"' 2>/dev/null)"
for target in cvmfs gpu slurm t3; do
    grep -qx "${target}" <<<"${check_comp}"
done

# Nothing root-owned is writable by group or others, and the user can read it all.
if find /opt/scigethelpers-cli /usr/local/bin/before-notebook.d/46-scigethelpers-cli.sh /etc/profile.d/scigethelpers-cli.sh /etc/bash.bashrc.d/scigethelpers-cli.sh \
        ! -type l \( -perm /022 -o ! -readable \) -print | grep .; then
    echo "bad permissions on the files above" >&2
    exit 1
fi
echo "scigethelpers: cite, kernel, uv, check, info and agent preflight work"
