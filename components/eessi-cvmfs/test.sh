#!/bin/bash
# Component test for eessi-cvmfs: runs on the OS layer with its CVMFS client.
# Mounts nothing (a build has no FUSE); test/eessi-cvmfs-smoke.sh tests the live mount.
set -euo pipefail
repository=software.eessi.io

assert_fails() {
    if "$@" >/dev/null 2>&1; then
        echo "FAIL: expected failure: $*" >&2
        exit 1
    fi
}

# CVMFS client resolves software.eessi.io to EESSI's mirrors and key.
config="$(cvmfs_config showconfig "${repository}")"
grep -q '^CVMFS_KEYS_DIR=/etc/cvmfs/keys/eessi\.io ' <<<"${config}"
grep -q '^CVMFS_USE_GEOAPI=yes ' <<<"${config}"
grep -qE '^CVMFS_SERVER_URL=.*eessi.*(/cvmfs/software\.eessi\.io|@fqrn@)' <<<"${config}"
grep -q 'BEGIN PUBLIC KEY' /etc/cvmfs/keys/eessi.io/eessi.io.pub

# Start hook sets software.eessi.io by default, appends to a component default
# (such as 18-neurodesk-cvmfs.sh), and respects an explicit operator override.
hook=/usr/local/bin/before-notebook.d/19-eessi-cvmfs.sh
[ "$(env -u SCIDESKTOP_CVMFS_REPOSITORIES bash -c ". ${hook}; echo \"\${SCIDESKTOP_CVMFS_REPOSITORIES}\"")" = "${repository}" ]
[ "$(SCIDESKTOP_CVMFS_REPOSITORIES=neurodesk.ardc.edu.au _SCIDESKTOP_CVMFS_REPOS_DEFAULT=1 bash -c ". ${hook}; echo \"\${SCIDESKTOP_CVMFS_REPOSITORIES}\"")" = "neurodesk.ardc.edu.au,${repository}" ]
[ "$(SCIDESKTOP_CVMFS_REPOSITORIES=other.example.org bash -c ". ${hook}; echo \"\${SCIDESKTOP_CVMFS_REPOSITORIES}\"")" = "other.example.org" ]
[ "$(printf '%s\n' "$(basename "${hook}")" 20-cvmfs | sort | head -n 1)" = "$(basename "${hook}")" ]
test -x /usr/local/bin/before-notebook.d/20-cvmfs

# Lmod modulepath provider is silent when EESSI is unmounted or disabled.
[ -z "$(/etc/scidesktop/modulepath.d/65-eessi)" ]
[ -z "$(SCIDESKTOP_CVMFS_MODE=disabled /etc/scidesktop/modulepath.d/65-eessi)" ]

# Dynamic app hook leaves SCIDESKTOP_APP_DIRS untouched when EESSI is unmounted.
app_hook=/usr/local/bin/before-notebook.d/32-eessi-apps.sh
[ -z "$(env -u SCIDESKTOP_APP_DIRS bash -c ". ${app_hook}; echo \"\${SCIDESKTOP_APP_DIRS:-}\"")" ]

# Helpers parse cleanly and reject bad arguments (including empty --stack).
bash -n "${hook}" "${app_hook}" /etc/scidesktop/modulepath.d/65-eessi /usr/local/bin/eessi-launch /usr/local/bin/eessi-catalog
assert_fails /usr/local/bin/eessi-launch
assert_fails /usr/local/bin/eessi-launch ParaView paraview
assert_fails /usr/local/bin/eessi-launch --stack bad ParaView paraview
assert_fails /usr/local/bin/eessi-launch --stack "" ParaView paraview
assert_fails /usr/local/bin/eessi-launch --stack= ParaView paraview
assert_fails /usr/local/bin/eessi-launch --stack 2025.06 'ParaView;id' paraview
assert_fails /usr/local/bin/eessi-launch --bogus ParaView paraview

# eessi-launch honors --stack, exact module names, and fallback to package name.
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/modroot"
cat >"${tmp}/mock-lmod.sh" <<'EOF'
module() {
    local sub="$1" mod="$2"
    echo "LOAD:${mod}" >> "${MOCK_LMOD_LOG}"
    if [ "${mod}" = "${MOCK_LMOD_FAIL:-}" ]; then
        return 1
    fi
    return 0
}
EOF
MOCK_LMOD_LOG="${tmp}/lmod.log" EESSI_MODULE_ROOT="${tmp}/modroot" EESSI_LMOD_INIT="${tmp}/mock-lmod.sh" \
    /usr/local/bin/eessi-launch --stack 2025.06 -- ParaView/6.0.1-foss-2025b echo ok-exact >"${tmp}/launch.out"
grep -q '^ok-exact$' "${tmp}/launch.out"
[ "$(cat "${tmp}/lmod.log")" = "$(printf 'LOAD:EESSI/2025.06\nLOAD:ParaView/6.0.1-foss-2025b')" ]

# Exact module missing falls back to package name.
: >"${tmp}/lmod.log"
MOCK_LMOD_LOG="${tmp}/lmod.log" MOCK_LMOD_FAIL="ParaView/6.0.1-foss-2025b" \
    EESSI_MODULE_ROOT="${tmp}/modroot" EESSI_LMOD_INIT="${tmp}/mock-lmod.sh" \
    /usr/local/bin/eessi-launch --stack 2025.06 -- ParaView/6.0.1-foss-2025b echo ok-fallback >"${tmp}/launch.out" 2>"${tmp}/launch.err"
grep -q '^ok-fallback$' "${tmp}/launch.out"
grep -q 'falling back to ParaView' "${tmp}/launch.err"
[ "$(cat "${tmp}/lmod.log")" = "$(printf 'LOAD:EESSI/2025.06\nLOAD:ParaView/6.0.1-foss-2025b\nLOAD:ParaView')" ]

# Explicit --stack fails instead of silently substituting another stack.
: >"${tmp}/lmod.log"
assert_fails env MOCK_LMOD_LOG="${tmp}/lmod.log" MOCK_LMOD_FAIL="EESSI/2023.06" \
    EESSI_MODULE_ROOT="${tmp}/modroot" EESSI_LMOD_INIT="${tmp}/mock-lmod.sh" \
    /usr/local/bin/eessi-launch --stack 2023.06 -- ParaView echo nope

# Built-in fallback output when no synced cache exists.
out="$(EESSI_CACHE_DIR="${tmp}/empty-cache" /usr/local/bin/eessi-catalog)"
grep -q 'ParaView (EESSI)' <<<"${out}"
grep -q 'GNU Octave (EESSI)' <<<"${out}"
grep -q 'GROMACS' <<<"${out}"
empty_modroot="${tmp}/empty-modroot"
mkdir -p "${empty_modroot}"
out_empty="$(EESSI_CACHE_DIR="${tmp}/empty-cache" EESSI_MODULE_ROOT="${empty_modroot}" /usr/local/bin/eessi-catalog)"
grep -q 'GROMACS' <<<"${out_empty}"

# URL derivation from /etc/sciget/catalogs.json ignores disabled and non-HTTPS entries.
cat >"${tmp}/catalogs.json" <<'EOF'
[
  {"name": "neuroimaging", "url": "https://apps-catalog.scigetorg.workers.dev/neuroimaging/apps.json", "use": true},
  {"name": "disabled", "url": "https://apps-catalog.scigetorg.workers.dev/microscopy/apps.json", "use": false},
  {"name": "insecure", "url": "http://example.org/datascience/apps.json", "use": true},
  {"name": "datascience", "url": "https://apps-catalog.scigetorg.workers.dev/datascience/apps.json"}
]
EOF
urls="$(SCIGET_CATALOGS_FILE="${tmp}/catalogs.json" /usr/local/bin/eessi-catalog urls)"
[ "${urls}" = "$(printf 'url:https://apps-catalog.scigetorg.workers.dev/neuroimaging/eessi.json\nurl:https://apps-catalog.scigetorg.workers.dev/datascience/eessi.json')" ]

# Sync from local eessi.json fixtures merges domains, deduplicates launchers,
# preserves canonical tile slugs, validates exec argv, and isolates EESSI category.
cat >"${tmp}/neuro.eessi.json" <<'EOF'
{
  "schemaVersion": 1,
  "backend": "eessi",
  "explicitSelectionRequired": true,
  "cvmfsRepo": "software.eessi.io",
  "stacks": ["2025.06", "2023.06"],
  "tools": {
    "paraview": {
      "package": "ParaView",
      "categories": ["visualization"],
      "description": "3D visualization",
      "apps": {
        "ParaView 6.0.1 (EESSI/2025.06)": {
          "backend": "eessi",
          "stack": "2025.06",
          "module": "ParaView/6.0.1-foss-2025b",
          "exec": ["paraview"],
          "gui": true,
          "show_in_menu": true
        },
        "ParaView 5.12.0 (EESSI/2023.06)": {
          "backend": "eessi",
          "stack": "2023.06",
          "module": "ParaView/5.12.0-foss-2023b",
          "exec": ["paraview"],
          "gui": true,
          "show_in_menu": true
        }
      }
    },
    "r-bundle-bioconductor": {
      "package": "R-bundle-Bioconductor",
      "categories": ["molecular biology", "statistics"],
      "description": "",
      "apps": {
        "R + Bioconductor 3.22 (EESSI/2025.06)": {
          "backend": "eessi",
          "stack": "2025.06",
          "module": "R-bundle-Bioconductor/3.22-foss-2025b-R-4.5.2",
          "exec": ["R"],
          "gui": false,
          "terminal": true,
          "show_in_menu": true
        }
      }
    },
    "biopython": {
      "package": "Biopython",
      "categories": ["programming"],
      "description": "Library only",
      "apps": {
        "Biopython 1.86 (EESSI/2025.06)": {
          "backend": "eessi",
          "stack": "2025.06",
          "module": "Biopython/1.86-gfbf-2025b",
          "exec": [],
          "gui": false,
          "show_in_menu": false
        }
      }
    }
  }
}
EOF

cat >"${tmp}/data.eessi.json" <<'EOF'
{
  "schemaVersion": 1,
  "backend": "eessi",
  "explicitSelectionRequired": true,
  "cvmfsRepo": "software.eessi.io",
  "stacks": ["2025.06"],
  "tools": {
    "paraview": {
      "package": "ParaView",
      "categories": ["visualization"],
      "description": "3D visualization",
      "apps": {
        "ParaView 6.0.1 (EESSI/2025.06)": {
          "backend": "eessi",
          "stack": "2025.06",
          "module": "ParaView/6.0.1-foss-2025b",
          "exec": ["paraview"],
          "gui": true,
          "show_in_menu": true
        }
      }
    },
    "r-bundle-cran": {
      "package": "R-bundle-CRAN",
      "categories": ["programming", "statistics"],
      "description": "R with CRAN packages",
      "apps": {
        "R + CRAN 2025.11 (EESSI/2025.06)": {
          "backend": "eessi",
          "stack": "2025.06",
          "module": "R-bundle-CRAN/2025.11-foss-2025b",
          "exec": ["R"],
          "gui": false,
          "terminal": true,
          "show_in_menu": true
        }
      }
    }
  }
}
EOF

cache="${tmp}/cache"
files="${tmp}/neuro.eessi.json:${tmp}/data.eessi.json"
EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${files}" /usr/local/bin/eessi-catalog sync
apps_dir="$(EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${files}" /usr/local/bin/eessi-catalog apps-dir)"

# Canonical desktop filenames exist, newest stack wins eessi-paraview.desktop,
# and library-only Biopython creates no launcher.
test -f "${apps_dir}/eessi-paraview.desktop"
test -f "${apps_dir}/eessi-r-cran.desktop"
test -f "${apps_dir}/eessi-r-bioconductor.desktop"
[ ! -e "${apps_dir}/eessi-biopython.desktop" ]
grep -q '^Exec=/usr/local/bin/eessi-launch --stack 2025\.06 -- ParaView/6\.0\.1-foss-2025b paraview$' "${apps_dir}/eessi-paraview.desktop"
grep -q '^X-Scidesktop-Category=EESSI$' "${apps_dir}/eessi-paraview.desktop"
grep -q '^Exec=/usr/local/bin/eessi-launch --stack 2025\.06 -- R-bundle-CRAN/2025\.11-foss-2025b xfce4-terminal --disable-server --title="R + CRAN 2025\.11 (EESSI/2025\.06)" -x R$' "${apps_dir}/eessi-r-cran.desktop"
grep -q '^Exec=/usr/local/bin/eessi-launch --stack 2025\.06 -- R-bundle-Bioconductor/3\.22-foss-2025b-R-4\.5\.2 xfce4-terminal --disable-server --title="R + Bioconductor 3\.22 (EESSI/2025\.06)" -x R$' "${apps_dir}/eessi-r-bioconductor.desktop"
[ "$(find "${apps_dir}" -maxdepth 1 -name '*.desktop' | wc -l)" -eq 4 ]

# Shared-home isolation: syncing a different source set into the same cache
# keeps the first source set's launchers intact.
EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/data.eessi.json" /usr/local/bin/eessi-catalog sync
data_apps_dir="$(EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/data.eessi.json" /usr/local/bin/eessi-catalog apps-dir)"
[ "${data_apps_dir}" != "${apps_dir}" ]
test -f "${apps_dir}/eessi-r-bioconductor.desktop"
test -f "${data_apps_dir}/eessi-r-cran.desktop"
[ ! -e "${data_apps_dir}/eessi-r-bioconductor.desktop" ]

# Unsynced source set falls back to static /etc/scidesktop/eessi-apps.d.
[ "$(EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/neuro.eessi.json" /usr/local/bin/eessi-catalog apps-dir)" = "/etc/scidesktop/eessi-apps.d" ]

# Live catalog output uses the synced JSON.
synced_out="$(EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${files}" /usr/local/bin/eessi-catalog)"
grep -q 'ParaView 6\.0\.1 (EESSI/2025\.06)' <<<"${synced_out}"
grep -q 'Biopython \[2025\.06\]: Biopython/1\.86-gfbf-2025b' <<<"${synced_out}"

# Malformed catalog inputs are strictly rejected and preserve existing caches:
# 1) unsafe exec arg
cat >"${tmp}/bad-exec.eessi.json" <<'EOF'
{
  "schemaVersion": 1,
  "backend": "eessi",
  "explicitSelectionRequired": true,
  "cvmfsRepo": "software.eessi.io",
  "stacks": ["2025.06"],
  "tools": {
    "evil": {
      "package": "Evil",
      "categories": ["programming"],
      "apps": {
        "Evil": {
          "backend": "eessi",
          "stack": "2025.06",
          "module": "Evil/1.0",
          "exec": ["sh", "-c;id"],
          "show_in_menu": true
        }
      }
    }
  }
}
EOF
assert_fails env EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/bad-exec.eessi.json" /usr/local/bin/eessi-catalog sync

# 2) multi-document stream (invalid JSON object followed by valid one)
cat "${tmp}/bad-exec.eessi.json" "${tmp}/data.eessi.json" >"${tmp}/multi-doc.eessi.json"
assert_fails env EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/multi-doc.eessi.json" /usr/local/bin/eessi-catalog sync

# 3) trailing newline in exec argument (Oniguruma $ vs \z regression)
cat >"${tmp}/bad-newline.eessi.json" <<'EOF'
{
  "schemaVersion": 1,
  "backend": "eessi",
  "explicitSelectionRequired": true,
  "cvmfsRepo": "software.eessi.io",
  "stacks": ["2025.06"],
  "tools": {
    "evil": {
      "package": "Evil",
      "categories": ["programming"],
      "apps": {
        "Evil": {
          "backend": "eessi",
          "stack": "2025.06",
          "module": "Evil/1.0",
          "exec": ["paraview\n"],
          "show_in_menu": true
        }
      }
    }
  }
}
EOF
assert_fails env EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/bad-newline.eessi.json" /usr/local/bin/eessi-catalog sync

# 4) numeric description (must be rejected upfront, never partial render)
cat >"${tmp}/bad-desc.eessi.json" <<'EOF'
{
  "schemaVersion": 1,
  "backend": "eessi",
  "explicitSelectionRequired": true,
  "cvmfsRepo": "software.eessi.io",
  "stacks": ["2025.06"],
  "tools": {
    "paraview": {
      "package": "ParaView",
      "categories": ["visualization"],
      "description": 123,
      "apps": {
        "ParaView": {
          "backend": "eessi",
          "stack": "2025.06",
          "module": "ParaView/6.0.1-foss-2025b",
          "exec": ["paraview"],
          "show_in_menu": true
        }
      }
    }
  }
}
EOF
assert_fails env EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/bad-desc.eessi.json" /usr/local/bin/eessi-catalog sync

# 5) embedded NUL in description or app label (must never cross field boundaries)
cat >"${tmp}/bad-nul-desc.eessi.json" <<'EOF'
{
  "schemaVersion": 1,
  "backend": "eessi",
  "explicitSelectionRequired": true,
  "cvmfsRepo": "software.eessi.io",
  "stacks": ["2025.06"],
  "tools": {
    "paraview": {
      "package": "ParaView",
      "categories": ["visualization"],
      "description": "ok\u0000injected",
      "apps": {
        "ParaView": {
          "backend": "eessi",
          "stack": "2025.06",
          "module": "ParaView/6.0.1-foss-2025b",
          "exec": ["paraview"],
          "show_in_menu": true
        }
      }
    }
  }
}
EOF
assert_fails env EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/bad-nul-desc.eessi.json" /usr/local/bin/eessi-catalog sync

cat >"${tmp}/bad-nul-label.eessi.json" <<'EOF'
{
  "schemaVersion": 1,
  "backend": "eessi",
  "explicitSelectionRequired": true,
  "cvmfsRepo": "software.eessi.io",
  "stacks": ["2025.06"],
  "tools": {
    "paraview": {
      "package": "ParaView",
      "categories": ["visualization"],
      "description": "3D visualization",
      "apps": {
        "ParaView\u0000Evil": {
          "backend": "eessi",
          "stack": "2025.06",
          "module": "ParaView/6.0.1-foss-2025b",
          "exec": ["paraview"],
          "show_in_menu": true
        }
      }
    }
  }
}
EOF
assert_fails env EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/bad-nul-label.eessi.json" /usr/local/bin/eessi-catalog sync

# 6) non-HTTPS URL
assert_fails env EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_URLS="http://example.org/eessi.json" /usr/local/bin/eessi-catalog sync

# No abandoned .staging.* directories remain after failed syncs.
[ -z "$(find "${cache}" -type d -name '.staging.*')" ]

# Previously synced cache remains intact after all rejected sync attempts.
test -f "${apps_dir}/eessi-paraview.desktop"

# Relative EESSI_CATALOG_FILES paths resolve against cwd so two directories
# with identically named catalog.json files get distinct cache namespaces.
mkdir -p "${tmp}/rel-a" "${tmp}/rel-b"
cp "${tmp}/neuro.eessi.json" "${tmp}/rel-a/catalog.json"
cp "${tmp}/data.eessi.json" "${tmp}/rel-b/catalog.json"
(cd "${tmp}/rel-a" && EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="catalog.json" /usr/local/bin/eessi-catalog sync)
(cd "${tmp}/rel-b" && EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="catalog.json" /usr/local/bin/eessi-catalog sync)
rel_a_dir="$(cd "${tmp}/rel-a" && EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="catalog.json" /usr/local/bin/eessi-catalog apps-dir)"
rel_b_dir="$(cd "${tmp}/rel-b" && EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="catalog.json" /usr/local/bin/eessi-catalog apps-dir)"
[ "${rel_a_dir}" != "${rel_b_dir}" ]
test -f "${rel_a_dir}/eessi-r-bioconductor.desktop"
[ ! -e "${rel_a_dir}/eessi-r-cran.desktop" ]
test -f "${rel_b_dir}/eessi-r-cran.desktop"
[ ! -e "${rel_b_dir}/eessi-r-bioconductor.desktop" ]

# Immutable snapshot apps-dir: a subsequent same-source refresh that removes a
# tool updates apps-dir to a new snapshot while keeping the previously registered
# snapshot intact for already-running Jupyter sessions; a later malformed sync
# on the same source preserves the current snapshot and leaves no staging dir.
cp "${tmp}/neuro.eessi.json" "${tmp}/mutable.eessi.json"
EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/mutable.eessi.json" /usr/local/bin/eessi-catalog sync
snap1_dir="$(EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/mutable.eessi.json" /usr/local/bin/eessi-catalog apps-dir)"
case "${snap1_dir}" in
    */snapshots/sync-*/applications) ;;
    *) echo "FAIL: expected immutable snapshot path, got ${snap1_dir}" >&2; exit 1 ;;
esac
test -f "${snap1_dir}/eessi-r-bioconductor.desktop"
cp "${tmp}/data.eessi.json" "${tmp}/mutable.eessi.json"
EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/mutable.eessi.json" /usr/local/bin/eessi-catalog sync
snap2_dir="$(EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/mutable.eessi.json" /usr/local/bin/eessi-catalog apps-dir)"
[ "${snap1_dir}" != "${snap2_dir}" ]
test -f "${snap1_dir}/eessi-r-bioconductor.desktop"
test -f "${snap2_dir}/eessi-r-cran.desktop"
[ ! -e "${snap2_dir}/eessi-r-bioconductor.desktop" ]
cp "${tmp}/bad-nul-desc.eessi.json" "${tmp}/mutable.eessi.json"
assert_fails env EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/mutable.eessi.json" /usr/local/bin/eessi-catalog sync
[ "$(EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/mutable.eessi.json" /usr/local/bin/eessi-catalog apps-dir)" = "${snap2_dir}" ]
[ -z "$(find "${cache}" -type d -name '.staging.*')" ]

# Concurrent same-source syncs serialize cleanly without snapshot collisions.
cp "${tmp}/data.eessi.json" "${tmp}/mutable.eessi.json"
pids=()
for _ in 1 2 3 4 5 6; do
    EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/mutable.eessi.json" /usr/local/bin/eessi-catalog sync &
    pids+=("$!")
done
for pid in "${pids[@]}"; do
    wait "${pid}"
done
snap_conc_dir="$(EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/mutable.eessi.json" /usr/local/bin/eessi-catalog apps-dir)"
test -f "${snap_conc_dir}/eessi-paraview.desktop"
test -f "${snap_conc_dir}/eessi-r-cran.desktop"
[ -z "$(find "${cache}" -type d -name '.staging.*')" ]

# Secondary launcher filenames never overwrite another tool's canonical filename.
cat >"${tmp}/collision.eessi.json" <<'EOF'
{
  "schemaVersion": 1,
  "backend": "eessi",
  "explicitSelectionRequired": true,
  "cvmfsRepo": "software.eessi.io",
  "stacks": ["2025.06", "2023.06"],
  "tools": {
    "foo": {
      "package": "Foo",
      "categories": ["programming"],
      "description": "Primary Foo",
      "apps": {
        "Foo 2.0 (EESSI/2025.06)": {
          "backend": "eessi",
          "stack": "2025.06",
          "module": "Foo/2.0",
          "exec": ["foo"],
          "show_in_menu": true
        },
        "Foo 1.0 (EESSI/2023.06)": {
          "backend": "eessi",
          "stack": "2023.06",
          "module": "Foo/1.0",
          "exec": ["foo"],
          "show_in_menu": true
        }
      }
    },
    "foo-2023-06-1": {
      "package": "FooLegacy",
      "categories": ["programming"],
      "description": "Distinct tool whose canonical slug matches Foo's first secondary candidate",
      "apps": {
        "FooLegacy 1.0 (EESSI/2025.06)": {
          "backend": "eessi",
          "stack": "2025.06",
          "module": "FooLegacy/1.0",
          "exec": ["foolegacy"],
          "show_in_menu": true
        }
      }
    }
  }
}
EOF
EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/collision.eessi.json" /usr/local/bin/eessi-catalog sync
coll_dir="$(EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/collision.eessi.json" /usr/local/bin/eessi-catalog apps-dir)"
[ "$(find "${coll_dir}" -maxdepth 1 -name '*.desktop' | wc -l)" -eq 3 ]
grep -q '^Exec=/usr/local/bin/eessi-launch --stack 2025\.06 -- Foo/2\.0 foo$' "${coll_dir}/eessi-foo.desktop"
grep -q '^Exec=/usr/local/bin/eessi-launch --stack 2025\.06 -- FooLegacy/1\.0 foolegacy$' "${coll_dir}/eessi-foo-2023-06-1.desktop"
grep -q '^Exec=/usr/local/bin/eessi-launch --stack 2023\.06 -- Foo/1\.0 foo$' "${coll_dir}/eessi-foo-2023-06-2.desktop"

# Whitespace-only app labels are rejected upfront so they can never claim
# canonical slots or suppress valid labels during deduplication.
cat >"${tmp}/blank-label.eessi.json" <<'EOF'
{
  "schemaVersion": 1,
  "backend": "eessi",
  "explicitSelectionRequired": true,
  "cvmfsRepo": "software.eessi.io",
  "stacks": ["2025.06"],
  "tools": {
    "paraview": {
      "package": "ParaView",
      "categories": ["visualization"],
      "apps": {
        "   ": {
          "backend": "eessi",
          "stack": "2025.06",
          "module": "ParaView/6.0.1-foss-2025b",
          "exec": ["paraview"],
          "show_in_menu": true
        }
      }
    }
  }
}
EOF
assert_fails env EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/blank-label.eessi.json" /usr/local/bin/eessi-catalog sync

# Newlines in EESSI_CATALOG_FILES are rejected rather than silently loading a
# prefix file that happens to exist.
assert_fails env EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="$(printf '%s\n%s' "${tmp}/data.eessi.json" "${tmp}/nonexistent.json")" /usr/local/bin/eessi-catalog sync

# Staging reaper removes unlocked abandoned .staging.* dirs older than 10m
# without disturbing an aged .staging.* dir held by an active sync's flock.
live_ns_dir="$(dirname "$(dirname "$(dirname "${coll_dir}")")")"
live_stage="${live_ns_dir}/snapshots/.staging.live01"
dead_stage="${live_ns_dir}/snapshots/.staging.dead01"
mkdir -p "${live_stage}" "${dead_stage}"
touch -d '30 minutes ago' "${live_stage}" "${dead_stage}"
exec {live_stage_fd}>"${live_stage}/.in-use"
flock -x "${live_stage_fd}"
EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/collision.eessi.json" /usr/local/bin/eessi-catalog sync
test -d "${live_stage}"
[ ! -e "${dead_stage}" ]
exec {live_stage_fd}>&-
rm -rf "${live_stage}"

# 32-eessi-apps.sh stages a container-local session copy when mounted (dropping
# privileges for sync and staging when invoked as root), keeps session launchers
# intact even if shared-home snapshots age out and are pruned, respects
# XDG_CACHE_HOME when refresh is disabled, and falls back to static on error.
chmod 0755 "${tmp}"
chmod 0644 "${tmp}/neuro.eessi.json" "${tmp}/data.eessi.json"
install -d -m 0755 -o jovyan "${tmp}/hook-cache" "${tmp}/session-apps"
mounted_dirs="$(env -u SCIDESKTOP_APP_DIRS EESSI_MODULE_ROOT="${tmp}/modroot" \
    EESSI_CACHE_DIR="${tmp}/hook-cache" EESSI_SESSION_APPS_ROOT="${tmp}/session-apps" \
    EESSI_CATALOG_FILES="${files}" \
    bash -c ". ${app_hook}; echo \"\${SCIDESKTOP_APP_DIRS}\"")"
hook_session_dir="${mounted_dirs#/opt/sciget/applications:}"
[ "${mounted_dirs}" = "/opt/sciget/applications:${hook_session_dir}" ]
case "${hook_session_dir}" in
    "${tmp}/session-apps/scidesktop-eessi-apps."*) ;;
    *) echo "FAIL: expected container-local session dir, got ${hook_session_dir}" >&2; exit 1 ;;
esac
test -f "${hook_session_dir}/eessi-paraview.desktop"
[ "$(stat -c '%U' "${hook_session_dir}/eessi-paraview.desktop")" = "jovyan" ]
# Age the cached snapshot past 24h and refresh twice; the session's staged
# launcher files remain intact for long-running Jupyter sessions.
hook_snap_dir="$(dirname "$(EESSI_CACHE_DIR="${tmp}/hook-cache" EESSI_CATALOG_FILES="${files}" /usr/local/bin/eessi-catalog apps-dir)")"
touch -d '48 hours ago' "${hook_snap_dir}"
EESSI_CACHE_DIR="${tmp}/hook-cache" EESSI_CATALOG_FILES="${files}" /usr/local/bin/eessi-catalog sync
EESSI_CACHE_DIR="${tmp}/hook-cache" EESSI_CATALOG_FILES="${files}" /usr/local/bin/eessi-catalog sync
[ ! -e "${hook_snap_dir}" ]
test -f "${hook_session_dir}/eessi-paraview.desktop"

# With refresh disabled, 32-eessi-apps.sh honors XDG_CACHE_HOME just like CLI.
install -d -m 0755 -o jovyan "${tmp}/xdg-cache"
su -s /bin/bash jovyan -c "XDG_CACHE_HOME='${tmp}/xdg-cache' EESSI_CATALOG_FILES='${tmp}/data.eessi.json' /usr/local/bin/eessi-catalog sync"
xdg_dirs="$(env -u SCIDESKTOP_APP_DIRS -u EESSI_CACHE_DIR \
    XDG_CACHE_HOME="${tmp}/xdg-cache" EESSI_MODULE_ROOT="${tmp}/modroot" \
    EESSI_SESSION_APPS_ROOT="${tmp}/session-apps" \
    EESSI_CATALOG_FILES="${tmp}/data.eessi.json" \
    SCIDESKTOP_EESSI_CATALOG_REFRESH=no \
    bash -c ". ${app_hook}; echo \"\${SCIDESKTOP_APP_DIRS}\"")"
xdg_session_dir="${xdg_dirs#/opt/sciget/applications:}"
[ "${xdg_session_dir}" != "/etc/scidesktop/eessi-apps.d" ]
test -f "${xdg_session_dir}/eessi-r-cran.desktop"
[ ! -e "${xdg_session_dir}/eessi-r-bioconductor.desktop" ]

install -d -m 0755 -o jovyan "${tmp}/fail-cache"
fallback_dirs="$(env -u SCIDESKTOP_APP_DIRS EESSI_MODULE_ROOT="${tmp}/modroot" \
    EESSI_CACHE_DIR="${tmp}/fail-cache" EESSI_SESSION_APPS_ROOT="${tmp}/session-apps" \
    EESSI_CATALOG_FILES="${tmp}/nonexistent.json" \
    bash -c ". ${app_hook} 2>/dev/null; echo \"\${SCIDESKTOP_APP_DIRS}\"")"
[ "${fallback_dirs}" = "/opt/sciget/applications:/etc/scidesktop/eessi-apps.d" ]

# Static fallback .desktop entries also belong to the explicit EESSI category.
for f in /etc/scidesktop/eessi-apps.d/*.desktop; do
    grep -q '^X-Scidesktop-Category=EESSI$' "${f}"
done

# Permissions and manifest.
[ "$(stat -c '%a %u' /etc/cvmfs/domain.d /etc/cvmfs/keys/eessi.io /etc/scidesktop/eessi-apps.d /etc/scidesktop/eessi-catalog.d)" = "$(printf '755 0\n755 0\n755 0\n755 0')" ]
test -r /opt/scidesktop/manifest.d/eessi-cvmfs.json
