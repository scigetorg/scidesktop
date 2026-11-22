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
for command in cite kernel uv check info; do grep -q "^  ${command} " <<<"${help}"; done
if grep -E '^  (jobs|update|test|t3|agent|astra|lightcone)' <<<"${help}"; then
    echo "scigethelpers --help lists a command this image does not have" >&2
    exit 1
fi
[ "$(scigethelpers help check)" = "$(scigethelpers check --help)" ]
if scigethelpers inf 2>"${HOME}/error"; then exit 1; fi
grep -q "Did you mean 'info'?" "${HOME}/error"
scigethelpers --version | grep -q '^scigethelpers {cli_sha256: [0-9a-f]\{64\}}$'
[ "$(readlink -f "$(command -v scigethelpers-kernel)")" = /opt/scigethelpers-cli/lib/scigethelpers_kernel.py ]

# check: Slurm is not running yet, no CVMFS repo configured here, there is no GPU.
scigethelpers check gpu | grep -q '^\[SKIP\] gpu'
scigethelpers check cvmfs | grep -q '^\[SKIP\] cvmfs'
if SCIDESKTOP_CVMFS_REPOSITORIES=neurodesk.ardc.edu.au scigethelpers check cvmfs >"${HOME}/cvmfs"; then exit 1; fi
grep -q '^\[FAIL\] cvmfs' "${HOME}/cvmfs"
SCIDESKTOP_CVMFS_MODE=disabled SCIDESKTOP_CVMFS_REPOSITORIES=neurodesk.ardc.edu.au scigethelpers check cvmfs | grep -q '^\[SKIP\] cvmfs'
if scigethelpers check slurm >"${HOME}/slurm"; then exit 1; fi
grep -q '^\[FAIL\] slurm' "${HOME}/slurm"
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
kill -TERM "${supervisor}"; wait "${supervisor}"; supervisor=""

# info names the image's components and the container's resources.
info="$(scigethelpers info)"
grep -q '^Image: .*scigethelpers-cli' <<<"${info}"
grep -qE '^CPUs: +[0-9.]+$' <<<"${info}"
grep -qE '^Memory: +[0-9.]+ GiB$' <<<"${info}"
grep -qE '^GPU: +none visible$' <<<"${info}"

# cite: Lmod's site package records a loaded sciget module, and the command
# turns the record into citations from a catalogue (a local one here: a build
# has no business on the network).
. /usr/local/bin/before-notebook.d/46-scigethelpers-cli.sh
[ "${LMOD_PACKAGE_PATH}" = /opt/scigethelpers-cli/lmod ]
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
SCIGETHELPERS_CITE_CATALOGUE_URL="file://${HOME}/apps.json" scigethelpers cite >/dev/null
grep -q 'smoketool (v1.2, built 2026-01-01) was run in Neurodesk/Scidesktop (Renton et al., 2024).' "${HOME}/CITATIONS.md"
grep -q 'https://doi.org/10.0000/smoke' "${HOME}/CITATIONS.md"

# kernel: no container kernel yet, and a module that is not a container's is
# refused with a reason, without a traceback.
scigethelpers kernel list | grep -q '^No container kernels registered'
if scigethelpers kernel add nosuchtool/1.0 2>"${HOME}/error"; then exit 1; fi
grep -q "scigethelpers-kernel: error: could not load module 'nosuchtool/1.0'" "${HOME}/error"
if grep -q Traceback "${HOME}/error"; then exit 1; fi

# uv: offline refusal checks and atomic rebuild rollback on failure.
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
! grep -q "unmanaged" "${HOME}/error"
if scigethelpers uv remove "${uvproj}" 2>"${HOME}/error"; then exit 1; fi
grep -q "No uv kernel registration" "${HOME}/error"

# Nothing root-owned is writable by group or others, and the user can read it all.
if find /opt/scigethelpers-cli /usr/local/bin/before-notebook.d/46-scigethelpers-cli.sh /etc/profile.d/scigethelpers-cli.sh /etc/bash.bashrc.d/scigethelpers-cli.sh \
        ! -type l \( -perm /022 -o ! -readable \) -print | grep .; then
    echo "bad permissions on the files above" >&2
    exit 1
fi
echo "scigethelpers: cite, kernel, check and info work"
