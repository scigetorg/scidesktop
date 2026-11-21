#!/bin/bash
# The component's own test: runs on the OS layer as the notebook user, with
# Lmod, the Slurm component and the Jupyter environment's Python.
set -euo pipefail
export HOME="$(mktemp -d)"
cd "${HOME}"
supervisor=""
# Says where a check failed: the checks themselves print nothing.
trap 'echo "neurodesk-cli test: the check at line ${LINENO} failed" >&2' ERR
trap '[ -z "${supervisor}" ] || kill "${supervisor}" 2>/dev/null || true' EXIT

# The command lists what this image has, and nothing it does not.
help="$(neurodesk --help)"
for command in cite kernel check info; do grep -q "^  ${command} " <<<"${help}"; done
if grep -E '^  (uv|jobs|update|test|t3|agent|astra|lightcone)' <<<"${help}"; then
    echo "neurodesk --help lists a command this image does not have" >&2
    exit 1
fi
[ "$(neurodesk help check)" = "$(neurodesk check --help)" ]
if neurodesk inf 2>"${HOME}/error"; then exit 1; fi
grep -q "Did you mean 'info'?" "${HOME}/error"
neurodesk --version | grep -q '^neurodesk {cli_sha256: [0-9a-f]\{64\}}$'
[ "$(readlink -f "$(command -v neurodesk-kernel)")" = /opt/neurodesk-cli/lib/neurodesk_kernel.py ]

# check: Slurm is not running yet, CVMFS is not mounted, there is no GPU.
neurodesk check gpu | grep -q '^\[SKIP\] gpu'
if neurodesk check cvmfs >"${HOME}/cvmfs"; then exit 1; fi
grep -q '^\[FAIL\] cvmfs' "${HOME}/cvmfs"
SCIDESKTOP_CVMFS_MODE=disabled neurodesk check cvmfs | grep -q '^\[SKIP\] cvmfs'
if neurodesk check slurm >"${HOME}/slurm"; then exit 1; fi
grep -q '^\[FAIL\] slurm' "${HOME}/slurm"
# With the session's queue, the check passes and names its partition. The
# queue gets ports of this test's own: on some builders the tests of several
# components run at once and share one network.
controller_port="$(shuf -i 20000-39999 -n 1)"
export SCIDESKTOP_SLURM_PORTS="${controller_port},$(( controller_port + 20000 ))"
/opt/slurm/bin/slurm-session run >"${HOME}/slurm-session.log" 2>&1 &
supervisor=$!
/opt/slurm/bin/slurm-session wait
checked="$(neurodesk check slurm)" || true
[ "${checked}" = "[PASS] slurm  partitions: scidesktop*" ] || { echo "neurodesk check slurm: ${checked}" >&2; false; }
kill -TERM "${supervisor}"; wait "${supervisor}"; supervisor=""

# info names the image's components and the container's resources.
info="$(neurodesk info)"
grep -q '^Image: .*neurodesk-cli' <<<"${info}"
grep -qE '^CPUs: +[0-9.]+$' <<<"${info}"
grep -qE '^Memory: +[0-9.]+ GiB$' <<<"${info}"
grep -qE '^GPU: +none visible$' <<<"${info}"

# cite: Lmod's site package records a loaded Neurodesk module, and the
# command turns the record into citations from a catalogue (a local one here:
# a build has no business on the network).
. /usr/local/bin/before-notebook.d/46-neurodesk-cli.sh
[ "${LMOD_PACKAGE_PATH}" = /opt/neurodesk-cli/lmod ]
modules="${HOME}/.local/share/sciget/modules/neuroimaging"
mkdir -p "${modules}/smoketool" "${HOME}/other/othertool"
echo 'whatis("smoke")' > "${modules}/smoketool/1.2.lua"
echo 'whatis("other")' > "${HOME}/other/othertool/1.0.lua"
bash -lc "module use '${modules}' '${HOME}/other' && module load smoketool/1.2 othertool/1.0" >/dev/null 2>&1
log="${HOME}/.local/state/neurodesk/module-usage.tsv"
[ "$(cut -f 1,2 "${log}")" = "$(printf 'smoketool\t1.2')" ]
cat > "${HOME}/apps.json" <<'JSON'
{"smoketool": {"apps": {"smoketool 1.2": {"version": "20260101", "exec": "", "image": "smoketool_1.2"}},
               "categories": ["programming"], "citation": "Smoke, A. (2026). A tool. https://doi.org/10.0000/smoke"}}
JSON
NEURODESKTOP_CITE_CATALOGUE_URL="file://${HOME}/apps.json" neurodesk cite >/dev/null
grep -q 'smoketool (v1.2, built 2026-01-01) was run in Neurodesk (Renton et al., 2024).' "${HOME}/CITATIONS.md"
grep -q 'https://doi.org/10.0000/smoke' "${HOME}/CITATIONS.md"

# kernel: no container kernel yet, and a module that is not a container's is
# refused with a reason, without a traceback.
neurodesk kernel list | grep -q '^No container kernels registered'
if neurodesk kernel add nosuchtool/1.0 2>"${HOME}/error"; then exit 1; fi
grep -q "neurodesk-kernel: error: could not load module 'nosuchtool/1.0'" "${HOME}/error"
if grep -q Traceback "${HOME}/error"; then exit 1; fi

# Nothing root-owned is writable by group or others, and the user can read it all.
if find /opt/neurodesk-cli /usr/local/bin/before-notebook.d/46-neurodesk-cli.sh /etc/profile.d/neurodesk-cli.sh /etc/bash.bashrc.d/neurodesk-cli.sh \
        ! -type l \( -perm /022 -o ! -readable \) -print | grep .; then
    echo "bad permissions on the files above" >&2
    exit 1
fi
echo "neurodesk: cite, kernel, check and info work"
