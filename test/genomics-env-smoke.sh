#!/bin/bash
# End-to-end check of an image that copies the genomics-env component.
#
#   ./test/genomics-env-smoke.sh [image]
#
# Verifies:
#   - `genomics` kernel is registered and executes Biopython FASTA parsing,
#     AnnData (.h5ad) + MuData (.h5mu) roundtrip, Scanpy QC/PCA/Leiden clustering,
#     Polars/PyArrow, and YAML/JSON-schema Viash config inspection
#   - Default `python3` kernel remains on /opt/conda
#   - Domain EESSI genomics catalog notes and launcher tiles (app-eessi-r-bioconductor)
#     register cleanly when EESSI is mounted

set -uo pipefail

IMAGE="${1:-genomicsdesktop}"
NAME="genomics-env-smoke-$$"
TOKEN="genomics-smoke"
EESSI_STUB=""
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

cleanup() {
    docker logs "${NAME}" >"/tmp/${NAME}.log" 2>&1 || true
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
    [ -z "${EESSI_STUB}" ] || rm -rf "${EESSI_STUB}"
}
trap cleanup EXIT

EESSI_STUB="$(mktemp -d)"
chmod 0755 "${EESSI_STUB}"

echo "genomics-env smoke: ${IMAGE}"
docker run -d --name "${NAME}" --shm-size=2g -e JUPYTER_TOKEN="${TOKEN}" \
    -v "${EESSI_STUB}:/cvmfs/software.eessi.io/init/modules:ro" \
    "${IMAGE}" start-notebook.py >/dev/null \
    || { echo "  FAIL  container did not start"; exit 1; }

ready=0
for _ in $(seq 1 120); do
    if docker exec "${NAME}" curl -fsS --max-time 10 -o /dev/null "http://127.0.0.1:8888/api" 2>/dev/null; then
        ready=1
        break
    fi
    sleep 1
done
if [ "${ready}" -ne 1 ]; then
    fail "notebook server did not become ready within 120s"
    exit 1
fi

docker exec -i "${NAME}" /opt/conda/bin/python - "${TOKEN}" <<'PY' && pass "genomics kernel, Biopython/AnnData/MuData/Scanpy/nf-core checks passed" || fail "genomics kernel, Biopython/AnnData/MuData/Scanpy/nf-core checks passed"
import json
import sys
import urllib.request
import uuid
import websocket

token = sys.argv[1]
base = "http://127.0.0.1:8888"
headers = {"Authorization": f"token {token}"}

def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(base + path, data=data, method=method, headers=headers)
    if data is not None:
        r.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(r, timeout=30) as resp:
        raw = resp.read()
        return json.loads(raw) if raw else None

specs = req("GET", "/api/kernelspecs")["kernelspecs"]
assert "genomics" in specs, f"missing genomics kernel: {list(specs)}"
assert specs["python3"]["spec"]["argv"][0].startswith("/opt/conda/"), specs["python3"]["spec"]["argv"]

def run_code(kernel_name, code):
    k = req("POST", "/api/kernels", {"name": kernel_name})
    kid = k["id"]
    try:
        ws = websocket.create_connection(
            f"ws://127.0.0.1:8888/api/kernels/{kid}/channels?token={token}",
            timeout=120,
        )
        msg_id = uuid.uuid4().hex
        ws.send(json.dumps({
            "header": {
                "msg_id": msg_id,
                "username": "smoke",
                "session": uuid.uuid4().hex,
                "msg_type": "execute_request",
                "version": "5.3",
            },
            "parent_header": {},
            "metadata": {},
            "content": {
                "code": code,
                "silent": False,
                "store_history": False,
                "user_expressions": {},
                "allow_stdin": False,
            },
            "buffers": [],
            "channel": "shell",
        }))
        out, err = [], []
        while True:
            msg = json.loads(ws.recv())
            if msg.get("parent_header", {}).get("msg_id") != msg_id:
                continue
            mtype = msg["msg_type"]
            if mtype == "stream":
                out.append(msg["content"]["text"])
            elif mtype == "error":
                err.append(f'{msg["content"]["ename"]}: {msg["content"]["evalue"]}')
            elif mtype == "status" and msg["content"]["execution_state"] == "idle":
                break
        ws.close()
        if err:
            raise AssertionError("; ".join(err))
        return "".join(out).strip()
    finally:
        req("DELETE", f"/api/kernels/{kid}")

gen_out = run_code("genomics", """
import io, os, pathlib, site, sys, tempfile
import numpy as np
import scipy, pandas, polars, pyarrow, h5py, zarr, dask, xarray, numba
import sklearn, statsmodels, matplotlib, seaborn, plotly
import Bio, anndata as ad, scanpy as sc, mudata as md, igraph, leidenalg, umap
import yaml, jsonschema, nf_core, watermark
from Bio import SeqIO

assert sys.executable.startswith("/opt/genomics-env/"), sys.executable
assert site.ENABLE_USER_SITE is False, f"expected user site disabled, got {site.ENABLE_USER_SITE}"
assert os.environ.get("SCIDESKTOP_NEXTFLOW_CONFIG") == "/etc/scidesktop/nextflow/scidesktop.config"
work = pathlib.Path(tempfile.mkdtemp())

# 1. Biopython FASTA parsing and reverse complement
fasta = io.StringIO(">gene1\\nATGGCCATTGTAATGGGCCGCTGAAAGGGTGCCCGATAG\\n")
rec = next(SeqIO.parse(fasta, "fasta"))
assert rec.id == "gene1" and len(rec.seq) == 39
assert str(rec.seq.translate(to_stop=True)) == "MAIVMGR"

# 2. Synthetic single-cell AnnData + MuData (.h5ad / .h5mu) roundtrip & Scanpy PCA/Leiden
rng = np.random.default_rng(42)
counts = rng.poisson(lam=4.0, size=(40, 20)).astype(np.float32)
adata = ad.AnnData(X=counts)
adata.obs_names = [f"cell_{i}" for i in range(40)]
adata.var_names = [f"gene_{j}" for j in range(20)]
sc.pp.normalize_total(adata, target_sum=1e4)
sc.pp.log1p(adata)
sc.pp.pca(adata, n_comps=5)
sc.pp.neighbors(adata, n_neighbors=8, n_pcs=5)
sc.tl.leiden(adata, flavor="igraph", n_iterations=2, directed=False)
h5ad_path = work / "cells.h5ad"
adata.write_h5ad(h5ad_path)
reloaded_ad = ad.read_h5ad(h5ad_path)
assert reloaded_ad.shape == (40, 20) and "leiden" in reloaded_ad.obs

mdata = md.MuData({"rna": reloaded_ad})
h5mu_path = work / "multi.h5mu"
mdata.write_h5mu(h5mu_path)
reloaded_md = md.read_h5mu(h5mu_path)
assert "rna" in reloaded_md.mod and reloaded_md.mod["rna"].shape == (40, 20)

# 3. YAML + JSON Schema validation (Viash config / nextflow_schema inspection)
cfg = yaml.safe_load("name: demo\\narguments:\\n  - name: --input\\n    type: file\\n")
jsonschema.validate(cfg, {"type": "object", "required": ["name", "arguments"]})

print("GENOMICS_OK", reloaded_ad.shape, sc.__version__, md.__version__, Bio.__version__)
""")
assert "GENOMICS_OK" in gen_out, gen_out

base_out = run_code("python3", "import sys; print(sys.executable)")
assert base_out.startswith("/opt/conda/"), base_out
PY

servers="$(docker exec "${NAME}" curl -fsS -H "Authorization: token ${TOKEN}" \
    "http://127.0.0.1:8888/server-proxy/servers-info" 2>/dev/null || true)"
if grep -q '"app-eessi-r-bioconductor"' <<<"${servers}"; then
    pass "JupyterLab launcher registers app-eessi-r-bioconductor when EESSI is mounted"
else
    fail "JupyterLab launcher registers app-eessi-r-bioconductor when EESSI is mounted"
fi
if grep -q '"app-eessi-fastqc"' <<<"${servers}"; then
    pass "JupyterLab launcher keeps merged domain app-eessi-fastqc even after live EESSI sync"
else
    fail "JupyterLab launcher keeps merged domain app-eessi-fastqc even after live EESSI sync"
fi

if docker exec -u jovyan "${NAME}" bash -lc '
    set -euo pipefail
    # Cold-cache fallback shows bundled FastQC launcher and domain genomics notes.
    cold_out="$(EESSI_CACHE_DIR="$(mktemp -d)" eessi-catalog list)"
    grep -q "FastQC (EESSI)" <<<"${cold_out}"
    grep -q "SAMtools" <<<"${cold_out}"

    # Synced fixture test: live entry wins collision, absent bundled FastQC is
    # merged, explicitly hidden fastqc (show_in_menu=false) stays hidden, and
    # domain genomics notes remain visible.
    fx="$(mktemp -d)"
    cat > "${fx}/live.eessi.json" <<'\''JSON'\''
{
  "schemaVersion": 1,
  "backend": "eessi",
  "explicitSelectionRequired": true,
  "cvmfsRepo": "software.eessi.io",
  "stacks": ["2025.06"],
  "tools": {
    "r-bundle-bioconductor": {
      "package": "R-bundle-Bioconductor",
      "categories": ["biology"],
      "apps": {
        "R + Bioconductor Live (EESSI/2025.06)": {
          "backend": "eessi",
          "stack": "2025.06",
          "module": "R-bundle-Bioconductor/3.22-foss-2025b-R-4.5.2",
          "exec": ["R"],
          "gui": false,
          "terminal": true,
          "show_in_menu": true
        }
      }
    }
  }
}
JSON
    EESSI_CACHE_DIR="${fx}/cache" EESSI_CATALOG_FILES="${fx}/live.eessi.json" eessi-catalog sync
    sync_out="$(EESSI_CACHE_DIR="${fx}/cache" EESSI_CATALOG_FILES="${fx}/live.eessi.json" eessi-catalog list)"
    grep -q "R + Bioconductor Live (EESSI/2025\.06)" <<<"${sync_out}"
    grep -q "FastQC (EESSI)" <<<"${sync_out}"
    grep -q "SAMtools" <<<"${sync_out}"
    sdir="$(EESSI_CACHE_DIR="${fx}/cache" EESSI_CATALOG_FILES="${fx}/live.eessi.json" EESSI_SESSION_APPS_ROOT="${fx}/sapps" eessi-catalog session-apps-dir)"
    grep -q "^Name=R + Bioconductor Live (EESSI/2025\.06)$" "${sdir}/eessi-r-bioconductor.desktop"
    test -f "${sdir}/eessi-fastqc.desktop"

    cat > "${fx}/hide-fastqc.eessi.json" <<'\''JSON'\''
{
  "schemaVersion": 1,
  "backend": "eessi",
  "explicitSelectionRequired": true,
  "cvmfsRepo": "software.eessi.io",
  "stacks": ["2025.06"],
  "tools": {
    "fastqc": {
      "package": "FastQC",
      "categories": ["biology"],
      "apps": {
        "FastQC Hidden (EESSI/2025.06)": {
          "backend": "eessi",
          "stack": "2025.06",
          "module": "FastQC/0.12.1-Java-11",
          "exec": ["fastqc"],
          "gui": true,
          "show_in_menu": false
        }
      }
    },
    "r-bundle-bioconductor": {
      "package": "R-bundle-Bioconductor",
      "categories": ["biology"],
      "apps": {
        "R + Bioconductor Hidden (EESSI/2025.06)": {
          "backend": "eessi",
          "stack": "2025.06",
          "module": "R-bundle-Bioconductor/3.22-foss-2025b-R-4.5.2",
          "exec": ["R"],
          "gui": false,
          "terminal": true,
          "show_in_menu": false
        }
      }
    }
  }
}
JSON
    EESSI_CACHE_DIR="${fx}/cache" EESSI_CATALOG_FILES="${fx}/hide-fastqc.eessi.json" eessi-catalog sync
    hdir="$(EESSI_CACHE_DIR="${fx}/cache" EESSI_CATALOG_FILES="${fx}/hide-fastqc.eessi.json" EESSI_SESSION_APPS_ROOT="${fx}/happs" eessi-catalog session-apps-dir)"
    [ ! -e "${hdir}/eessi-fastqc.desktop" ]
    [ ! -e "${hdir}/eessi-r-bioconductor.desktop" ]
    hlist="$(EESSI_CACHE_DIR="${fx}/cache" EESSI_CATALOG_FILES="${fx}/hide-fastqc.eessi.json" eessi-catalog list)"
    if grep -q "FastQC (EESSI)" <<<"${hlist}"; then exit 1; fi
    if grep -q "R + Bioconductor (EESSI)" <<<"${hlist}"; then exit 1; fi
    rm -rf "${fx}"
' 2>/dev/null; then
    pass "eessi-catalog fixture tests pass (live collision, FastQC merge, show_in_menu=false hide, cold-cache & synced notes)"
else
    fail "eessi-catalog fixture tests pass (live collision, FastQC merge, show_in_menu=false hide, cold-cache & synced notes)"
fi

bad_execs="$(docker exec "${NAME}" bash -c '
    for f in /etc/scidesktop/eessi-apps.d/*.desktop; do
        [ -f "${f}" ] || continue
        exec_line="$(sed -n "s/^Exec=//p" "${f}" | head -n 1)"
        case "${exec_line}" in
            *xfce4-terminal*)
                case "${exec_line}" in
                    *--disable-server*) ;;
                    *) echo "${f}: ${exec_line}" ;;
                esac
                ;;
        esac
    done
' 2>&1)"
if [ -z "${bad_execs}" ]; then
    pass "all xfce4-terminal EESSI desktop launchers pass --disable-server"
else
    fail "all xfce4-terminal EESSI desktop launchers pass --disable-server (${bad_execs})"
fi

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "genomics-env smoke: all checks passed"
else
    echo "genomics-env smoke: ${FAILED} check(s) failed; container log at /tmp/${NAME}.log"
fi
exit "${FAILED}"
