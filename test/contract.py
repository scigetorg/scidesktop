#!/usr/bin/env python3
"""Enforce the build conventions in docs/components.md.

    python3 test/contract.py static   # before building: Dockerfiles, bake file
    python3 test/contract.py layers   # after building: what each component writes

Exit status is non-zero when any rule is broken; each violation is printed
with the rule it breaks.
"""
import io
import json
import re
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BAKE = ROOT / "docker-bake.hcl"
ASSEMBLY = ROOT / "Dockerfile"
COMPONENTS = ROOT / "components"
OS_COMPONENT = "os-ubuntu"

# Bake variables that carry no "# renovate:" comment, and why.
NOT_RENOVATED = {
    "APT_SNAPSHOT": "moved by .github/workflows/apt-snapshot.yml",
    "CVMFS_CONFIG_VERSION": "no release feed to track",
    "NB_USER": "setting, not a version",
    "NB_UID": "setting, not a version",
    "NB_GID": "setting, not a version",
    "IMAGE": "output tag",
    "SCIGET_COMMIT": "tracked by its own Renovate rule (git-refs on main)",
    "SCIGET_SRC": "built from SCIGET_COMMIT",
}
# Instructions the assembly may use: image metadata a component cannot provide.
ASSEMBLY_ALLOWED = {"FROM", "COPY", "LABEL", "ENV", "EXPOSE", "HEALTHCHECK",
                    "ENTRYPOINT", "CMD", "WORKDIR", "USER", "ARG", "SHELL"}

problems = []


def fail(rule, msg):
    problems.append(f"[{rule}] {msg}")


def bake_print():
    out = subprocess.run(["docker", "buildx", "bake", "--print", "default", "test"],
                         cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def instructions(dockerfile):
    """(instruction, text) per logical line, continuations joined."""
    lines, cur = [], ""
    for raw in dockerfile.read_text().splitlines():
        line = raw.strip()
        if not cur and (not line or line.startswith("#")):
            continue
        if line.startswith("#"):
            continue
        cur += " " + line.rstrip("\\").strip() if cur else line.rstrip("\\").strip()
        if not line.endswith("\\"):
            lines.append((cur.split()[0].upper(), cur))
            cur = ""
    return lines


def component_names():
    return sorted(p.parent.name for p in COMPONENTS.glob("*/Dockerfile"))


def static():
    bake = bake_print()
    targets, groups = bake["target"], bake["group"]
    assembled = sorted(set(targets["scidesktop"]["contexts"]) - {"os"})

    # S1: the assembly only assembles.
    copied = []
    for ins, text in instructions(ASSEMBLY):
        if ins not in ASSEMBLY_ALLOWED:
            fail("S1", f"Dockerfile: {ins} is not allowed in the assembly; move it into a component: {text[:70]}")
        elif ins == "FROM" and text.split()[1:] != ["os"]:
            fail("S1", f"Dockerfile: the assembly must be FROM os, not: {text}")
        elif ins == "COPY":
            m = re.fullmatch(r"COPY --link --from=(\S+) / /", text)
            if not m:
                fail("S1", f"Dockerfile: COPY must be `COPY --link --from=<component> / /`: {text}")
            else:
                copied.append(m.group(1))
        elif ins == "ARG" and "=" in text:
            fail("S4", f"Dockerfile: ARG with a value; versions and settings live in docker-bake.hcl: {text}")
    # S2: every assembled component is copied exactly once.
    for u in assembled:
        if copied.count(u) != 1:
            fail("S2", f"Dockerfile: component {u} is a context of the scidesktop target but copied {copied.count(u)} times")
    for u in set(copied) - set(assembled):
        fail("S2", f"Dockerfile: copies {u}, which is not a context of the scidesktop target")

    # S3: every component has a target, a test target in group "test", and the
    # component/test stages.
    test_group = set(groups["test"]["targets"])
    for u in component_names():
        df = COMPONENTS / u / "Dockerfile"
        text = df.read_text()
        for t in (u, f"{u}-test"):
            if t not in targets:
                fail("S3", f"{u}: no bake target {t}")
        if f"{u}-test" not in test_group:
            fail("S3", f"{u}: {u}-test is not in the bake group \"test\"")
        if not re.search(r"^FROM \S+ AS test$", text, re.M):
            fail("S3", f"{u}: Dockerfile has no `test` stage")
        if u != OS_COMPONENT and not re.search(r"^FROM scratch AS component$", text, re.M):
            fail("S3", f"{u}: Dockerfile has no `FROM scratch AS component` stage")
        # S4: no values in component Dockerfiles.
        for ins, line in instructions(df):
            if ins == "ARG" and "=" in line:
                fail("S4", f"{u}: ARG with a value; put it in docker-bake.hcl: {line}")

    # S5: every bake variable is one line, and tracked by Renovate unless
    # listed in NOT_RENOVATED.
    lines = BAKE.read_text().splitlines()
    for i, line in enumerate(lines):
        m = re.match(r'variable "(\w+)"', line)
        if not m:
            continue
        name = m.group(1)
        if not re.fullmatch(r'variable "\w+" \{ default = "[^"]*" \}', line):
            fail("S5", f"docker-bake.hcl:{i+1}: {name} must be one line: variable \"{name}\" {{ default = \"...\" }}")
        renovated = i > 0 and lines[i - 1].startswith("# renovate: ")
        if not renovated and name not in NOT_RENOVATED and not name.endswith("_SHA256"):
            fail("S5", f"docker-bake.hcl:{i+1}: {name} has no `# renovate:` comment above it")


def component_tar(target):
    """Stream a target's filesystem and return {path: (type, mode, uid, gid)}."""
    # stderr goes to a file: a pipe left unread while the tar streams can
    # fill and deadlock both processes.
    errlog = tempfile.TemporaryFile()
    proc = subprocess.Popen(
        ["docker", "buildx", "bake", "--allow=fs.read=..", "--progress=quiet", target,
         "--set", f"{target}.output=type=tar,dest=-"],
        cwd=ROOT, stdout=subprocess.PIPE, stderr=errlog)
    entries, manifests = {}, {}
    with tarfile.open(fileobj=proc.stdout, mode="r|") as tar:
        for m in tar:
            path = "/" + m.name.lstrip("./").rstrip("/")
            if path == "/":
                continue
            kind = "dir" if m.isdir() else "link" if m.issym() else "file"
            entries[path] = (kind, m.mode & 0o7777, m.uid, m.gid)
            if path.startswith("/opt/scidesktop/manifest.d/") and m.isfile():
                manifests[path] = tar.extractfile(m).read()
    rc = proc.wait()
    errlog.seek(0)
    err = errlog.read().decode(errors="replace")
    if rc != 0:
        sys.exit(f"building {target} failed:\n{err}")
    return entries, manifests


def layers():
    bake = bake_print()
    assembled = sorted(set(bake["target"]["scidesktop"]["contexts"]) - {"os"})
    os_entries, _ = component_tar(OS_COMPONENT)
    print(f"  {OS_COMPONENT}: {len(os_entries)} entries")
    seen = {}  # path -> component, for non-directories
    dirs = {}  # path -> (meta, component)
    for u in assembled:
        entries, manifests = component_tar(u)
        print(f"  {u}: {len(entries)} entries")
        # L4: the component's manifest entry, valid JSON.
        want = f"/opt/scidesktop/manifest.d/{u}.json"
        if want not in manifests:
            fail("L4", f"{u}: no manifest entry {want}")
        else:
            try:
                json.loads(manifests[want])
            except ValueError as e:
                fail("L4", f"{u}: {want} is not valid JSON: {e}")
        for path, (kind, mode, uid, gid) in entries.items():
            if kind != "dir":
                # L1: one owner per file. L2: no shadowing the OS layer.
                if path in seen:
                    fail("L1", f"{path} is written by both {seen[path]} and {u}")
                seen[path] = u
                if path in os_entries:
                    fail("L2", f"{u}: {path} shadows a file in the OS layer")
            else:
                # L3: a directory a component also creates must match the existing
                # one, or the linked layer silently changes it.
                meta = (mode, uid, gid)
                if path in os_entries and os_entries[path][0] == "dir" and os_entries[path][1:] != meta:
                    fail("L3", f"{u}: {path} is {oct(mode)} {uid}:{gid}, the OS layer has "
                               f"{oct(os_entries[path][1])} {os_entries[path][2]}:{os_entries[path][3]}")
                if path in dirs and dirs[path][0] != meta:
                    fail("L3", f"{u}: {path} is {oct(mode)} {uid}:{gid}, {dirs[path][1]} has "
                               f"{oct(dirs[path][0][0])} {dirs[path][0][1]}:{dirs[path][0][2]}")
                dirs.setdefault(path, (meta, u))
            # L5: nothing root-owned is writable by group or others.
            if kind != "link" and uid == 0 and mode & 0o022:
                fail("L5", f"{u}: {path} is root-owned and group/other writable ({oct(mode)})")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "static":
        static()
    elif mode == "layers":
        layers()
    else:
        sys.exit(__doc__)
    for p in problems:
        print("  FAIL ", p)
    print(f"contract {mode}: {'all rules hold' if not problems else f'{len(problems)} violation(s)'}")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
