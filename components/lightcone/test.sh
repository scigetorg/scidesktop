#!/bin/bash
# The component's own test: runs on the OS layer as the notebook user, with
# nothing from the base image but the OS and jupyter-env's Python. No network,
# no Slurm: a stub sinfo on PATH plays the session's queue.
set -euo pipefail
HOME="$(mktemp -d)"
export HOME
stubs="$(mktemp -d)"
runtime="$(mktemp -d)"
export XDG_RUNTIME_DIR="${runtime}"
trap 'rm -rf "${HOME}" "${stubs}" "${runtime}"' EXIT
unset LC_COMPUTE_CONFIG SLURM_CONF

fail() { echo "FAIL: $*" >&2; exit 1; }

# The manifest names the versions that answer.
manifest=/opt/scidesktop/manifest.d/lightcone.json
version() { sed -n "s/.*\"$1\": \"\([^\"]*\)\".*/\1/p" "${manifest}"; }
[ "$(version lightcone-cli)" = 0.5.0 ] && [ "$(version astra-tools)" = 0.2.18 ] \
    && [ "$(version astra-spec)" = 0.0.14 ] || fail "manifest: $(cat "${manifest}")"
[ "$(command -v lc)" = /usr/local/bin/lc ] || fail "lc is $(command -v lc)"
[ "$(lc --version)" = "lc, version 0.5.0" ] || fail "lc --version: $(lc --version)"
/opt/lightcone/bin/python -c '
import importlib.metadata as m
assert m.version("astra-tools") == "0.2.18" and m.version("astra-spec") == "0.0.14"
import dask, distributed, lightcone'

# queue <partition> <cpus> <MB>: the session's queue as sinfo reports it,
# with another partition beside it that is not the default.
queue() {
    cat > "${stubs}/sinfo" <<STUB
#!/bin/sh
printf '%s\n' "debug 64 512000" "$1* $2 $3"
STUB
    chmod +x "${stubs}/sinfo"
}

# offers: name cpus GiB partition python, one line per offer, as lc reads the catalog.
offers() {
    lc compute resources --json | /opt/lightcone/bin/python -c '
import json, sys, yaml, os
offers = json.load(sys.stdin)["offers"]
path = os.environ.get("LC_COMPUTE_CONFIG") or os.path.join(
    os.environ.get("XDG_RUNTIME_DIR"), "scidesktop-lightcone-%d" % os.getuid(), "compute.yaml")
config = {o["name"]: o.get("config", {}) for o in yaml.safe_load(open(path))["offers"]} if os.path.exists(path) else {}
for o in offers:
    c = config.get(o["name"], {})
    print(o["name"], o["resources"]["cpus"], o["resources"]["memory"],
          c.get("partition"), c.get("python"))'
}

# A node smaller than Neurodesktop's 2 CPUs and 8 GiB in memory (a 4 GB
# container less the session's reserve): the standard shape shrinks to it.
queue scidesktop 16 3328
export PATH="${stubs}:${PATH}"
got="$(offers)"
want="standard 2 3.25 scidesktop /opt/lightcone/bin/python
node 16 3.25 scidesktop /opt/lightcone/bin/python"
[ "${got}" = "${want}" ] || fail "small node offers:
${got}"
catalog="${runtime}/scidesktop-lightcone-$(id -u)"
[ "$(stat -c '%u %a' "${catalog}")" = "$(id -u) 700" ] || fail "catalog directory: $(stat -c '%u %a' "${catalog}")"
grep -q 'memory: 3328MB' "${catalog}/compute.yaml" || fail "memory not in whole MB"
grep -q '^allow_local: false' "${catalog}/compute.yaml" || fail "local compute allowed"

# A big node: the standard shape is Neurodesktop's, which
# `lc compute launch --cpus 2 --memory 8` plans; the whole node is offered too.
queue mine 32 128000
got="$(offers)"
want="standard 2 8.0 mine /opt/lightcone/bin/python
node 32 125.0 mine /opt/lightcone/bin/python"
[ "${got}" = "${want}" ] || fail "big node offers:
${got}"
plan="$(lc compute launch --cpus 2 --memory 8 --dry-run --json)" || fail "dry run: ${plan}"
printf '%s' "${plan}" | /opt/lightcone/bin/python -c '
import json, sys
text = json.dumps(json.load(sys.stdin))
assert "standard" in text and "--partition=mine" in text, text' || fail "plan: ${plan}"

# A node exactly the standard shape is offered once.
queue scidesktop 2 8192
[ "$(offers | cut -d' ' -f1-3)" = "standard 2 8.0" ] || fail "exact node: $(offers)"

# The user's own catalog wins: LC_COMPUTE_CONFIG, then ~/.lightcone/compute.yaml.
mkdir -p "${HOME}/.lightcone"
printf 'allow_local: false\noffers:\n  - {name: mine, provider: slurm, resources: {cpus: 1, memory: 1}, max_nodes: 1, time: {default: 1h}}\n' \
    > "${HOME}/own.yaml"
[ "$(LC_COMPUTE_CONFIG="${HOME}/own.yaml" offers | cut -d' ' -f1-3)" = "mine 1 1.0" ] \
    || fail "LC_COMPUTE_CONFIG ignored"
cp "${HOME}/own.yaml" "${HOME}/.lightcone/compute.yaml"
rm -rf "${catalog}"
[ "$(offers | cut -d' ' -f1-3)" = "mine 1 1.0" ] || fail "the home compute.yaml was ignored"
[ ! -e "${catalog}" ] || fail "a catalog was written beside the user's own"
rm "${HOME}/.lightcone/compute.yaml"

# No queue, a cluster the session did not start, or a directory another user
# could change: lc runs unchanged, with its built-in local offer.
printf '#!/bin/sh\nexit 1\n' > "${stubs}/sinfo"
[ "$(offers | cut -d' ' -f1)" = local ] || fail "failing sinfo: $(offers)"
queue scidesktop 16 3328
[ "$(SLURM_CONF=/elsewhere/slurm.conf offers | cut -d' ' -f1)" = local ] || fail "host cluster: catalog written"
[ "$(offers | cut -d' ' -f1 | head -1)" = standard ] || fail "session queue: no catalog"
rm -rf "${catalog}"
mkdir -m 0777 "${catalog}"
chmod 0777 "${catalog}"
[ "$(offers 2>/dev/null | cut -d' ' -f1)" = local ] || fail "unsafe directory used"
warning="$(lc --version 2>&1 >/dev/null)"
[[ "${warning}" == *"not a private directory"* ]] || fail "unsafe directory not reported: ${warning}"

# Nothing root-owned is writable by group or others, and the user can read it all.
if find /opt/lightcone /usr/local/bin/lc ! -type l \( -perm /022 -o ! -readable \) -print | grep .; then
    fail "bad permissions on the files above"
fi
echo "lightcone: all checks passed"
