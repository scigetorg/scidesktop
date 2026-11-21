"""Build step: fits the upstream workshop content to this image.

    prepare.py <content dir> <upstream commit> <manifest file>

Run with the workshop interpreter (/opt/ai-ready/env), after both
environments and the kernelspec are installed.
"""

import importlib.metadata
import json
from pathlib import Path
import subprocess
import sys

content, commit, manifest = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])

# The workshop saves a tree model it trained itself. skops refuses to load
# this type unless it is listed beside the calibration types upstream trusts.
pipeline = content / "src/vep_pipeline.py"
source = pipeline.read_text()
needle = "            skops_trusted_types=[\n"
assert source.count(needle) == 1, "upstream changed skops_trusted_types; revisit this patch"
pipeline.write_text(source.replace(needle, needle + '                "sklearn.tree._tree.Tree",\n'))

# Upstream's notebooks name the default kernel, which here is Jupyter's own
# environment without the workshop's libraries.
kernel = json.loads(Path("/opt/ai-ready/share/jupyter/kernels/ai-ready/kernel.json").read_text())
notebooks = sorted((content / "notebooks").glob("*.ipynb"))
assert notebooks, "upstream ships no notebooks"
for notebook in notebooks:
    document = json.loads(notebook.read_text())
    document["metadata"]["kernelspec"] = {
        "name": "ai-ready",
        "display_name": kernel["display_name"],
        "language": kernel["language"],
    }
    notebook.write_text(json.dumps(document, indent=1, ensure_ascii=False) + "\n")


def airflow_version(package):
    code = f"import importlib.metadata as m; print(m.version({package!r}))"
    return subprocess.run(["/opt/ai-ready/airflow/bin/python", "-c", code],
                          check=True, capture_output=True, text=True).stdout.strip()


postgres = subprocess.run(["/opt/ai-ready/env/bin/postgres", "--version"],
                          check=True, capture_output=True, text=True).stdout.split()[-1]
manifest.write_text(json.dumps({
    "ai-ready-containers": commit,
    "apache-airflow": airflow_version("apache-airflow"),
    "mlflow": importlib.metadata.version("mlflow"),
    "postgresql": postgres,
    "python": ".".join(map(str, sys.version_info[:3])),
}) + "\n")
