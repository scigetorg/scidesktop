#!/bin/bash
# Component test for eessi-cvmfs: runs on the OS layer with its CVMFS client.
# Mounts nothing (a build has no FUSE); test/eessi-cvmfs-smoke.sh tests the live mount.
set -euo pipefail
repository=software.eessi.io

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

# Helpers parse cleanly and reject bad arguments.
bash -n "${hook}" "${app_hook}" /etc/scidesktop/modulepath.d/65-eessi /usr/local/bin/eessi-launch /usr/local/bin/eessi-catalog
! /usr/local/bin/eessi-launch >/dev/null 2>&1
! /usr/local/bin/eessi-launch ParaView paraview >/dev/null 2>&1
! /usr/local/bin/eessi-launch --stack bad ParaView paraview >/dev/null 2>&1
! /usr/local/bin/eessi-launch --stack 2025.06 'ParaView;id' paraview >/dev/null 2>&1
! /usr/local/bin/eessi-launch --bogus ParaView paraview >/dev/null 2>&1

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
! MOCK_LMOD_LOG="${tmp}/lmod.log" MOCK_LMOD_FAIL="EESSI/2023.06" \
    EESSI_MODULE_ROOT="${tmp}/modroot" EESSI_LMOD_INIT="${tmp}/mock-lmod.sh" \
    /usr/local/bin/eessi-launch --stack 2023.06 -- ParaView echo nope >/dev/null 2>&1

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

# Canonical desktop filenames exist, newest stack wins eessi-paraview.desktop,
# and library-only Biopython creates no launcher.
test -f "${cache}/current/applications/eessi-paraview.desktop"
test -f "${cache}/current/applications/eessi-r-cran.desktop"
test -f "${cache}/current/applications/eessi-r-bioconductor.desktop"
! test -e "${cache}/current/applications/eessi-biopython.desktop"
grep -q '^Exec=/usr/local/bin/eessi-launch --stack 2025\.06 -- ParaView/6\.0\.1-foss-2025b paraview$' "${cache}/current/applications/eessi-paraview.desktop"
grep -q '^X-Scidesktop-Category=EESSI$' "${cache}/current/applications/eessi-paraview.desktop"
grep -q '^Exec=/usr/local/bin/eessi-launch --stack 2025\.06 -- R-bundle-CRAN/2025\.11-foss-2025b xfce4-terminal --disable-server --title="R + CRAN 2025\.11 (EESSI/2025\.06)" -x R$' "${cache}/current/applications/eessi-r-cran.desktop"
grep -q '^Exec=/usr/local/bin/eessi-launch --stack 2025\.06 -- R-bundle-Bioconductor/3\.22-foss-2025b-R-4\.5\.2 xfce4-terminal --disable-server --title="R + Bioconductor 3\.22 (EESSI/2025\.06)" -x R$' "${cache}/current/applications/eessi-r-bioconductor.desktop"

# Exactly 4 launchers generated (ParaView 2025.06 deduplicated, ParaView 2023.06, R+CRAN, R+Bioconductor).
[ "$(find "${cache}/current/applications" -maxdepth 1 -name '*.desktop' | wc -l)" -eq 4 ]

# Live catalog output uses the synced JSON.
synced_out="$(EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${files}" /usr/local/bin/eessi-catalog)"
grep -q 'ParaView 6\.0\.1 (EESSI/2025\.06)' <<<"${synced_out}"
grep -q 'Biopython \[2025\.06\]: Biopython/1\.86-gfbf-2025b' <<<"${synced_out}"

# Malformed catalog JSON (unsafe exec arg, missing explicitSelectionRequired, non-HTTPS URL)
# is rejected and preserves the previously synced valid snapshot.
cat >"${tmp}/bad.eessi.json" <<'EOF'
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
! EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/bad.eessi.json" /usr/local/bin/eessi-catalog sync 2>/dev/null
! EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_URLS="http://example.org/eessi.json" /usr/local/bin/eessi-catalog sync 2>/dev/null
test -f "${cache}/current/applications/eessi-paraview.desktop"

# Source mismatch falls back to static /etc/scidesktop/eessi-apps.d instead of stale cache.
[ "$(EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${tmp}/neuro.eessi.json" /usr/local/bin/eessi-catalog apps-dir)" = "/etc/scidesktop/eessi-apps.d" ]
[ "$(EESSI_CACHE_DIR="${cache}" EESSI_CATALOG_FILES="${files}" /usr/local/bin/eessi-catalog apps-dir)" = "${cache}/current/applications" ]

# 32-eessi-apps.sh selects the live synced dir when mounted (dropping privileges
# when invoked as root), and falls back when refresh fails.
chmod 0755 "${tmp}"
chmod 0644 "${tmp}/neuro.eessi.json" "${tmp}/data.eessi.json"
install -d -m 0755 -o jovyan "${tmp}/hook-cache"
mounted_dirs="$(env -u SCIDESKTOP_APP_DIRS EESSI_MODULE_ROOT="${tmp}/modroot" \
    EESSI_CACHE_DIR="${tmp}/hook-cache" EESSI_CATALOG_FILES="${files}" \
    bash -c ". ${app_hook}; echo \"\${SCIDESKTOP_APP_DIRS}\"")"
[ "${mounted_dirs}" = "/opt/sciget/applications:${tmp}/hook-cache/current/applications" ]
[ "$(stat -c '%U' "${tmp}/hook-cache/current/applications/eessi-paraview.desktop")" = "jovyan" ]

install -d -m 0755 -o jovyan "${tmp}/fail-cache"
fallback_dirs="$(env -u SCIDESKTOP_APP_DIRS EESSI_MODULE_ROOT="${tmp}/modroot" \
    EESSI_CACHE_DIR="${tmp}/fail-cache" EESSI_CATALOG_FILES="${tmp}/nonexistent.json" \
    bash -c ". ${app_hook} 2>/dev/null; echo \"\${SCIDESKTOP_APP_DIRS}\"")"
[ "${fallback_dirs}" = "/opt/sciget/applications:/etc/scidesktop/eessi-apps.d" ]

# Static fallback .desktop entries also belong to the explicit EESSI category.
for f in /etc/scidesktop/eessi-apps.d/*.desktop; do
    grep -q '^X-Scidesktop-Category=EESSI$' "${f}"
done

# Permissions and manifest.
[ "$(stat -c '%a %u' /etc/cvmfs/domain.d /etc/cvmfs/keys/eessi.io /etc/scidesktop/eessi-apps.d /etc/scidesktop/eessi-catalog.d)" = "$(printf '755 0\n755 0\n755 0\n755 0')" ]
test -r /opt/scidesktop/manifest.d/eessi-cvmfs.json
