#!/usr/bin/env python3
"""Enforce the build conventions in docs/components.md.

    python3 test/contract.py static          # before building: Dockerfiles, bake file
    python3 test/contract.py layers          # after building: what each component writes
    python3 test/contract.py image <image> [ref]
                                             # a built image: the components it holds

Exit status is non-zero when any rule is broken; each violation is printed
with the rule it breaks.
"""
import json
import re
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BAKE = ROOT / "docker-bake.hcl"
IMAGES = ROOT / "images"
BASE_IMAGE = "scidesktop"
ASSEMBLY = IMAGES / BASE_IMAGE / "Dockerfile"
COMPONENTS = ROOT / "components"
OS_COMPONENT = "os-ubuntu"
# The one place that names architectures; everything else asks it.
TARGET_ARCH = COMPONENTS / "target-arch"
CI = ROOT / ".github" / "workflows" / "image.yml"
# Asking the machine instead of buildx's TARGETARCH.
ARCH_PROBE = re.compile(r"uname -m|dpkg --print-architecture")
# Where a component puts its part of the notebook server's configuration, and
# the one file that loads the parts (docs/components.md).
JUPYTER_PARTS = "etc/scidesktop/jupyter_server_config.d"
JUPYTER_LOADER = "jupyter-env/rootfs/usr/local/etc/jupyter/jupyter_server_config.py"
JUPYTER_ENV = re.compile(r"\bJUPYTER_(?:CONFIG_)?PATH\b")
MANIFESTS = "/opt/scidesktop/manifest.d"

# Bake variables that carry no "# renovate:" comment, and why.
NOT_RENOVATED = {
    "APT_SNAPSHOT": "moved by .github/workflows/apt-snapshot.yml",
    "CVMFS_CONFIG_VERSION": "no release feed to track",
    "NB_USER": "setting, not a version",
    "NB_UID": "setting, not a version",
    "NB_GID": "setting, not a version",
    "PLATFORM": "build setting",
    "IMAGE": "output tag",
    "MICRODESKTOP_IMAGE": "output tag",
    "DATADESKTOP_IMAGE": "output tag",
    "AIDESKTOP_IMAGE": "output tag",
    "NEURODESKTOP_IMAGE": "output tag",
    "SCIGET_COMMIT": "tracked by its own Renovate rule (git-refs on main)",
    "SCIGET_SRC": "built from SCIGET_COMMIT",
    "AI_READY_COMMIT": "tracked by its own Renovate rule (git-refs on main)",
    "AI_READY_SRC": "built from AI_READY_COMMIT",
    "FREEBROWSE_COMMIT": "tracked by its own Renovate rule (git-refs on main)",
    "FREEBROWSE_SRC": "built from FREEBROWSE_COMMIT",
    "NEUROGLANCER_COMMIT": "tracked by its own Renovate rule (git-refs on master)",
    "NEUROGLANCER_SRC": "built from NEUROGLANCER_COMMIT",
    "JUPYTERLAB_SLURM_COMMIT": "tracked by its own Renovate rule (git-refs on main)",
    "JUPYTERLAB_SLURM_SRC": "built from JUPYTERLAB_SLURM_COMMIT",
    "NF_NEURO_MODULES_COMMIT": "tracked by its own Renovate rule (git-refs on main)",
    "NF_NEURO_MODULES_SRC": "built from NF_NEURO_MODULES_COMMIT",
    "ANTIGRAVITY_ACP_VERSION": "pinned to T3 Code's embedded antigravityRelease.ts table (no public feed)",
    "ANTIGRAVITY_ACP_SHA256_AMD64": "pinned to T3 Code's embedded antigravityRelease.ts table",
    "ANTIGRAVITY_ACP_SHA256_ARM64": "pinned to T3 Code's embedded antigravityRelease.ts table",
}
# Instructions the assembly may use: image metadata a component cannot provide.
ASSEMBLY_ALLOWED = {"FROM", "COPY", "LABEL", "ENV", "EXPOSE", "HEALTHCHECK",
                    "ENTRYPOINT", "CMD", "WORKDIR", "USER", "ARG", "SHELL"}

problems = []


def fail(rule, msg):
    problems.append(f"[{rule}] {msg}")


def bake_print():
    # Components are named too: one that no image copies is otherwise absent.
    run = subprocess.run(["docker", "buildx", "bake", "--print", "default", "test", *component_names()],
                         cwd=ROOT, capture_output=True, text=True)
    if run.returncode:
        sys.exit(f"docker buildx bake --print failed:\n{run.stderr}")
    return json.loads(run.stdout)


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


def rel(path):
    return path.relative_to(ROOT)


def target_arch(naming, arch=None):
    out = subprocess.run([TARGET_ARCH, naming], env={"TARGETARCH": arch} if arch else {},
                         capture_output=True, text=True, check=True).stdout
    return out.split()


def component_names():
    return sorted(p.parent.name for p in COMPONENTS.glob("*/Dockerfile"))


def image_names():
    return sorted(p.name for p in IMAGES.iterdir() if p.is_dir())


def image_components(targets, image):
    """Components the image holds: its own and those of the images it is FROM."""
    components = set(component_names()) - {OS_COMPONENT}
    found = set()
    while image in targets:
        parent = None
        for context, source in targets[image].get("contexts", {}).items():
            if context in components and source == f"target:{context}":
                found.add(context)
            elif context == f"{source.removeprefix('target:')}-base":
                parent = source.removeprefix("target:")
        image = parent
    return found


def copied_components(targets):
    """Components that an image in images/ copies: the base's, and those a
    domain image adds. Each is a bake context of the image, named after its
    component target."""
    components = set(component_names()) - {OS_COMPONENT}
    return sorted({context for image in image_names()
                   for context, source in targets.get(image, {}).get("contexts", {}).items()
                   if context in components and source == f"target:{context}"})


def static():
    bake = bake_print()
    targets, groups = bake["target"], bake["group"]
    assembled = sorted(set(targets["scidesktop"]["contexts"]) - {"os"})

    # S1: the assembly only assembles.
    copied = []
    for ins, text in instructions(ASSEMBLY):
        if ins not in ASSEMBLY_ALLOWED:
            fail("S1", f"{rel(ASSEMBLY)}: {ins} is not allowed in the assembly; move it into a component: {text[:70]}")
        elif ins == "FROM" and text.split()[1:] != ["os"]:
            fail("S1", f"{rel(ASSEMBLY)}: the assembly must be FROM os, not: {text}")
        elif ins == "COPY":
            m = re.fullmatch(r"COPY --link --from=(\S+) / /", text)
            if not m:
                fail("S1", f"{rel(ASSEMBLY)}: COPY must be `COPY --link --from=<component> / /`: {text}")
            else:
                copied.append(m.group(1))
        elif ins == "ARG" and "=" in text:
            fail("S4", f"{rel(ASSEMBLY)}: ARG with a value; versions and settings live in docker-bake.hcl: {text}")
    # S2: every assembled component is copied exactly once.
    for u in assembled:
        if copied.count(u) != 1:
            fail("S2", f"{rel(ASSEMBLY)}: component {u} is a context of the scidesktop target but copied {copied.count(u)} times")
    for u in set(copied) - set(assembled):
        fail("S2", f"{rel(ASSEMBLY)}: copies {u}, which is not a context of the scidesktop target")

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

    # S7: the architecture comes from buildx. Nothing asks the machine, and a
    # conda environment has a lock for every architecture.
    arches = target_arch("list")
    for path in sorted(COMPONENTS.rglob("*")):
        if not path.is_file() or path == TARGET_ARCH or path.suffix == ".lock":
            continue
        try:
            text = path.read_text()
        except UnicodeDecodeError:
            continue
        for n, line in enumerate(text.splitlines(), 1):
            code = line.split("#", 1)[0]
            if ARCH_PROBE.search(code):
                fail("S7", f"{rel(path)}:{n}: asks the machine for its architecture; "
                           f"use TARGETARCH and components/target-arch: {line.strip()[:70]}")
    for env in sorted(COMPONENTS.glob("*/environment.yml")):
        for arch in arches:
            lock = env.with_name(f"{target_arch('conda', arch)[0]}.lock")
            if not lock.is_file():
                fail("S7", f"{rel(env.parent)}: no {lock.name} for {arch}; run ./lock")

    ci = sorted(re.findall(r"^ +- arch: (\S+)$", CI.read_text(), re.M))
    if ci != sorted(arches):
        fail("S7", f"{rel(CI)}: the build matrix has {', '.join(ci) or 'no architectures'}, "
                   f"components/target-arch lists {', '.join(arches)}")

    # S6: every folder in images/ is a bake target of the same name in group
    # "default", built from that folder. The stage a domain image builds is
    # FROM <base>-base, a bake context naming another image in images/: a
    # registry image would bypass the base built alongside it, and the base's
    # own name would resolve to whatever image of that tag is stored locally.
    images = image_names()
    for name in images:
        t = targets.get(name)
        if t is None:
            fail("S6", f"images/{name}: no bake target {name}")
            continue
        if name not in groups["default"]["targets"]:
            fail("S6", f"{name}: not in the bake group \"default\"")
        if (ROOT / t.get("context", ".")).resolve() != (IMAGES / name).resolve():
            fail("S6", f"{name}: the bake target's context is {t.get('context')}, not images/{name}")
            continue
        if name == BASE_IMAGE:
            continue
        df = IMAGES / name / t.get("dockerfile", "Dockerfile")
        if not df.is_file():
            fail("S6", f"{name}: no Dockerfile at {rel(df)}")
            continue
        # (stage name, FROM image) per stage; follow the built stage back
        # through earlier stages to the image it starts from.
        stages = []
        for ins, text in instructions(df):
            if ins == "FROM":
                words = [w for w in text.split()[1:] if not w.startswith("--")]
                stages.append((words[2].lower() if len(words) > 2 and words[1].lower() == "as" else None, words[0]))
        names = [s for s, _ in stages]
        i = len(stages) - 1
        if t.get("target"):
            i = names.index(t["target"].lower()) if t["target"].lower() in names else -1
        if i < 0:
            fail("S6", f"{name}: {rel(df)} has no stage {t.get('target')}")
            continue
        base = stages[i][1]
        while base.lower() in names[:i]:
            i = names.index(base.lower())
            base = stages[i][1]
        parent = base[:-len("-base")] if base.endswith("-base") else None
        if parent not in images or parent == name:
            fail("S6", f"{rel(df)}: the image must be FROM <image>-base for another image in images/, not {base}")
        elif t.get("contexts", {}).get(base) != f"target:{parent}":
            fail("S6", f"{name}: FROM {base} needs `contexts = {{ {base} = \"target:{parent}\" }}` in its bake target")
        # A domain image adds a component the way the assembly does: whole,
        # as a linked layer, built in the same bake run.
        for ins, text in instructions(df):
            m = re.match(r"COPY\b.*--from=(\S+)", text) if ins == "COPY" else None
            if not m or m.group(1) not in component_names():
                continue
            u = m.group(1)
            if text != f"COPY --link --from={u} / /":
                fail("S6", f"{rel(df)}: a component is copied whole, as `COPY --link --from={u} / /`: {text}")
            if t.get("contexts", {}).get(u) != f"target:{u}":
                fail("S6", f"{name}: copying {u} needs `{u} = \"target:{u}\"` in its bake target's contexts")
            if u in image_components(targets, parent):
                fail("S6", f"{rel(df)}: copies {u}, which {parent} already holds; remove the COPY and the context")
            # S8: a component brings its own Jupyter registration.
        for ins, text in instructions(df):
            if ins == "ENV" and JUPYTER_ENV.search(text):
                fail("S8", f"{rel(df)}: sets a Jupyter path; a component registers itself through "
                           f"/{JUPYTER_PARTS}/<component>.py and /usr/local/share/jupyter: {text[:70]}")

    # S8: one way to add to the notebook server's configuration. A component
    # ships /etc/scidesktop/jupyter_server_config.d/<component>.py, which adds
    # to shared settings and never assigns them; only the loader is a Jupyter
    # config file of its own.
    for path in sorted(COMPONENTS.glob("*/rootfs/**/*")):
        if not path.is_file():
            continue
        u, inside = path.relative_to(COMPONENTS).parts[0], path.relative_to(COMPONENTS).as_posix()
        if path.parent.as_posix().endswith(JUPYTER_PARTS):
            if path.name != f"{u}.py":
                fail("S8", f"{rel(path)}: a component's part of the Jupyter configuration is named {u}.py")
            for n, line in enumerate(path.read_text().splitlines(), 1):
                if re.match(r"\s*c\.ServerProxy\.servers\s*=[^=]", line):
                    fail("S8", f"{rel(path)}:{n}: assigns c.ServerProxy.servers, dropping other components' "
                               f"entries; use c.ServerProxy.servers.update(...)")
        elif path.name == "jupyter_server_config.py" and inside != JUPYTER_LOADER:
            fail("S8", f"{rel(path)}: a Jupyter config file of its own; move it to "
                       f"rootfs/{JUPYTER_PARTS}/{u}.py")

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
        checksum = re.fullmatch(r"(\w+_SHA256)(?:_([A-Z0-9]+))?", name)
        if not renovated and name not in NOT_RENOVATED and not checksum:
            fail("S5", f"docker-bake.hcl:{i+1}: {name} has no `# renovate:` comment above it")
        # A checksum that differs per architecture has a variable for each one.
        if checksum and checksum.group(2):
            for arch in arches:
                if f'variable "{checksum.group(1)}_{arch.upper()}" ' not in BAKE.read_text():
                    fail("S5", f"docker-bake.hcl:{i+1}: {name} has no {checksum.group(1)}_{arch.upper()} beside it")
            if checksum.group(2).lower() not in arches:
                fail("S5", f"docker-bake.hcl:{i+1}: {name} is for an architecture components/target-arch does not list")


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
    targets = bake_print()["target"]
    assembled = copied_components(targets)
    # Two components meet when some image holds both. Components no image
    # combines may be alternatives for one file, as the sciget catalogs are.
    together = [image_components(targets, image) for image in image_names()]
    os_entries, _ = component_tar(OS_COMPONENT)
    print(f"  {OS_COMPONENT}: {len(os_entries)} entries")
    seen = {}  # path -> components, for non-directories
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
                # L1: one owner per file in an image (except domain sciget-*
                # catalog components intentionally narrowing sciget-all's
                # /etc/sciget/catalogs.json). L2: no shadowing the OS layer.
                for other in seen.setdefault(path, []):
                    if path == "/etc/sciget/catalogs.json" and "sciget-all" in (other, u) \
                            and other.startswith("sciget-") and u.startswith("sciget-"):
                        continue
                    if any({other, u} <= held for held in together):
                        fail("L1", f"{path} is written by both {other} and {u}")
                seen[path].append(u)
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


def image(name, ref):
    """I1: a built image holds the components its bake target names, and no
    file of any other component. This is what keeps optional components out
    of the base."""
    expected = image_components(bake_print()["target"], name)
    others = sorted(set(component_names()) - {OS_COMPONENT} - expected)
    # Signs of a component: its manifest entry, its prefix, and each
    # integration file it ships in rootfs/.
    def integration_files(u):
        root = COMPONENTS / u / "rootfs"
        return {"/" + path.relative_to(root).as_posix() for path in root.rglob("*")
                if path.is_symlink() or path.is_file()}

    # A file the image's own components ship is theirs, also where another
    # image's component is an alternative for it (the sciget catalogs).
    own = set().union(*(integration_files(u) for u in expected))
    signs = {}
    for u in others:
        signs[f"{MANIFESTS}/{u}.json"] = u
        signs[f"/opt/{u}"] = u
        for path in integration_files(u) - own:
            signs[path] = u
    script = f'ls {MANIFESTS}; echo ---; for p in "$@"; do if [ -e "$p" ] || [ -L "$p" ]; then echo "$p"; fi; done'
    run = subprocess.run(["docker", "run", "--rm", "--entrypoint", "bash", ref, "-c", script, "_", *signs],
                         capture_output=True, text=True)
    if run.returncode:
        sys.exit(f"docker run {ref} failed:\n{run.stderr}")
    manifests, _, found = run.stdout.partition("---\n")
    held = {m.removesuffix(".json") for m in manifests.split()}
    for u in sorted(expected - held):
        fail("I1", f"{ref}: no manifest entry for {u}, which the {name} bake target copies")
    for path in found.split():
        fail("I1", f"{ref}: has {path} of component {signs[path]}, which the {name} bake target does not copy")
    print(f"  {ref}: {', '.join(sorted(expected))}; nothing of {', '.join(others) or 'no other component'}")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "static":
        static()
    elif mode == "layers":
        layers()
    elif mode == "image" and len(sys.argv) in (3, 4) and sys.argv[2] in image_names():
        image(sys.argv[2], sys.argv[-1])
    else:
        sys.exit(__doc__)
    for p in problems:
        print("  FAIL ", p)
    print(f"contract {mode}: {'all rules hold' if not problems else f'{len(problems)} violation(s)'}")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
