# scidesktop operator runbook

How to run scidesktop as a JupyterHub single-user image, what the platform
must provide, and how to check and triage a deployment. Deploy an image digest
or an immutable short-SHA tag from `ghcr.io/scigetorg/scidesktop`, not
`latest`.

Every tag is one image for amd64 and arm64; each node pulls its own
architecture.

| Tag | Moves | Use |
| --- | --- | --- |
| `<short sha>` (seven characters of the commit on `main`) | never | deployments |
| `<YYYY-MM-DD>` (UTC) | to the last build of that day | finding a build by date |
| `latest` | with every build of `main` | trying it out |
| `run-<number>-<arch>` | never | none: single-architecture parts of the tags above |

### GHCR build cache package

CI writes BuildKit layer caches on `main` pushes to
`ghcr.io/scigetorg/scidesktop-cache`. New organisation packages on GHCR start
private by default: after the first `main` push creates `scidesktop-cache`,
an org admin should set its visibility to **Public** (and confirm the
`scigetorg/scidesktop` repository has **Write** access under Package Settings
-> Manage Actions access) so fork pull requests and local developers can read
the cache anonymously without hitting a cold rebuild.

## Platform requirements

scidesktop exists to launch containerised tools with Apptainer, inside the
single-user pod and without privileges. That needs:

| Requirement | Why | Without it |
| --- | --- | --- |
| **Unprivileged user namespaces**: allowed by the node kernel, and not blocked by the pod's seccomp or AppArmor profile | Apptainer runs containers through user namespaces (setuid is off) | JupyterLab and the desktop start, but no containerised tool runs. Users see a warning in every terminal; the log says `[apptainer] WARNING` |
| `/dev/fuse` in the pod (optional) | mounting SIF files and writable overlays | unpacked containers (CVMFS, sandboxes) still run; SIF files do not |
| `/cvmfs` mounted by the node (optional) | fast, shared, on-demand delivery of containers | sciget cannot find containers that live on CVMFS |
| 2 GiB of shared memory at `/dev/shm`, at least 2 CPUs | the X server and the desktop | rendering errors; slow starts |

Platforms that cannot provide user namespaces (for example EKS Fargate, GKE
Autopilot, OpenShift's default security constraints) are not targets: use a
plain Jupyter image there.

**Reference configurations that work:**

- **neurocloud** (`neurodesk/neurocloud`): pods non-privileged, seccomp not set
  (unconfined), a `notebook` AppArmor profile from security-profiles-operator
  that allows Apptainer's mounts, CVMFS from the CVMFS CSI driver.
- **AIS** (`Australian-Imaging-Service/ais-jupyterhub`): the same, plus
  `/dev/fuse` from smarter-device-manager (`smarter-devices/fuse: 1` per pod).

On Ubuntu 24.04 and later nodes, check `sysctl
kernel.apparmor_restrict_unprivileged_userns`. When it is `1`, the pod's
AppArmor profile must allow user namespaces. Running unconfined is not always
enough: with the setting at `1`, a kernel 7.0 host (a GitHub runner) let the
user create a namespace but refused Apptainer's user mapping, while a kernel
6.8 host allowed both.

**Workstations (`docker run`):** Docker's default seccomp and AppArmor profiles
block user namespaces. Run with dropped capabilities, `no-new-privileges`, and
only the seccomp/AppArmor relaxation needed for unprivileged user namespaces:

```sh
docker run --rm -p 8888:8888 --shm-size=2g \
    --cap-drop ALL --security-opt no-new-privileges:true \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
    --device /dev/fuse \
    ghcr.io/scigetorg/scidesktop:<short-sha>
```

If terminals still say containers are unavailable, the host restricts user
namespaces as above; on a host you control, `sudo sysctl -w
kernel.apparmor_restrict_unprivileged_userns=0` lifts it until reboot.

## JupyterHub configuration

```python
c.KubeSpawner.image = "ghcr.io/scigetorg/scidesktop:<short-sha>"
c.KubeSpawner.cpu_guarantee = 2
c.KubeSpawner.cpu_limit = 2
c.KubeSpawner.container_security_context = {
    "runAsNonRoot": True,
    "allowPrivilegeEscalation": False,
    "capabilities": {"drop": ["ALL"]},
}

c.KubeSpawner.volumes = [
    {"name": "shm", "emptyDir": {"medium": "Memory", "sizeLimit": "2Gi"}},
    # The cluster's CVMFS CSI claim, or another read-only /cvmfs volume.
    {"name": "cvmfs", "persistentVolumeClaim": {"claimName": "cvmfs"}},
]
c.KubeSpawner.volume_mounts = [
    {"name": "shm", "mountPath": "/dev/shm"},
    {"name": "cvmfs", "mountPath": "/cvmfs", "readOnly": True,
     "mountPropagation": "HostToContainer"},
]
# Plus the cluster's AppArmor/seccomp settings from "Platform requirements".
# scidesktop ships zero SUID/SGID binaries and locks NoNewPrivs=1 in start.sh;
# mounting SIF files via /dev/fuse requires Linux >= 5.18 (unprivileged FUSE
# inside user namespaces).
```

Do not set `c.KubeSpawner.cmd`, `command` or `args` just to start Jupyter. The
image keeps docker-stacks' `start.sh` (hardened to drop privileges via `setpriv`
with `NoNewPrivs` and zero bounding capabilities instead of `sudo`), which
accepts the spawner's command and sets up the user. Only port 8888 listens
outside the pod; the desktop starts when the user first opens **Desktop** from
the launcher.

## Environment

| Variable | Default | Meaning |
| --- | --- | --- |
| `SCIDESKTOP_APPTAINER_SETUID` | unused | Removed for security hardening: Apptainer is built `--without-suid` and `starter-suid` is not shipped. Setting `yes` logs a warning and leaves setuid disabled. |
| `APPTAINER_HOME` | the notebook user's home | Set at start so Apptainer does not look the home up for the host uid, which fails under rootless Podman ("failed to add  as session directory"). An explicit value is kept. |
| `APPTAINER_NV` | `1` when the NVIDIA driver is loaded | Binds the host's NVIDIA devices and libraries into tool containers. Set `0` if a tool fails with `GLIBC_* not found` from a host library. |
| `VGL_DISPLAY` | auto-detected NVIDIA `/dev/dri/card*` (or `egl`) | VirtualGL EGL device for GPU-accelerated 3D rendering (`vglrun`). Also propagated as `APPTAINERENV_VGL_DISPLAY` so `sciget`/Apptainer `--cleanenv` containers inherit it. |
| `SCIDESKTOP_CVMFS_MODE` | `external` | `external`: use the `/cvmfs` the platform mounts. `internal`: mount inside the container (needs root, `/dev/fuse`, mount capability, an AppArmor profile that allows FUSE mounts, repository config and keys under `/etc/cvmfs`; with `docker run`: `--cap-add SYS_ADMIN --device /dev/fuse --security-opt apparmor=unconfined`). `disabled`: skip. |
| `SCIDESKTOP_CVMFS_REPOSITORIES` | `software.eessi.io`; `neurodesk.ardc.edu.au,software.eessi.io` in neurodesktop | Repositories to mount in `internal` mode, comma-separated. Images include `eessi-cvmfs` by default, and `neurodesktop` adds `neurodesk-cvmfs`. |
| `CVMFS_HTTP_PROXY`, `CVMFS_QUOTA_LIMIT`, `CVMFS_CACHE_BASE` | `DIRECT`, `5000`, `/var/lib/cvmfs` | CVMFS client settings in `internal` mode. |
| `CVMFS_NFILES` | `65536`, or the container's hard open-file limit when that is lower | The open-file limit the CVMFS client sets for itself in `internal` mode. The client refuses to mount when it may not raise the limit that far. |
| `SCIDESKTOP_SCIGET_REFRESH` | `yes` | Download sciget's catalogs in the background at start. |
| `SCIDESKTOP_SLURM` | `yes` | Start the session's Slurm queue, sized from `CPU_LIMIT` and `MEM_LIMIT`. It needs no privilege. `SCIDESKTOP_SLURM_PARTITION` and `SCIDESKTOP_SLURM_MEMORY_RESERVE_MB` are in [slurm.md](slurm.md). |
| `SELKIES_BASIC_AUTH_PASSWORD` | generated | The desktop's internal credential; generated per container when unset. |
| `CPU_LIMIT`, `MEM_LIMIT` | from the pod's cgroup | Set by KubeSpawner, or derived at start from the cgroup when it does not. `OMP_NUM_THREADS`, `MKL_NUM_THREADS`, `OPENBLAS_NUM_THREADS` and `NUMEXPR_NUM_THREADS` follow `CPU_LIMIT` unless set, so numerical libraries use the pod's CPUs. |

sciget's settings and catalog for every user are its system layer in
`/etc/sciget/`, read on every run beneath each user's own files: a user's
settings win and their catalogs come first, and `sciget doctor` names a user
file that hides a system one. `scidesktop` ships all published catalogs
(`neuroimaging`, `microscopy`, `datascience`, `dermatology`, `preclinical` and `molecular-imaging` via `sciget-all`); domain images
narrow that file to their community (`neuroimaging` in `neurodesktop`,
`microscopy` in `microdesktop`, `datascience` in `datadesktop` and `genomicsdesktop`,
`dermatology` in `dermdesktop`, `preclinical` in `preclinicaldesktop`,
`molecular-imaging` in `moleculardesktop`;
[images.md](images.md#tool-catalogs)).

## Deployment check

1. Start a single-user server. In its log, read the `[apptainer]` line (`user
   namespaces=yes` expected) and the `[cvmfs]` line, and check there is no
   `[apptainer] WARNING`.
2. Open JupyterLab, then **Desktop** from the launcher; the IceWM desktop
   should render within a few seconds.
3. In a terminal: no yellow "Containers are unavailable" message; `sciget find`
   lists the catalog; `apptainer exec` of a container from `/cvmfs` runs.
4. `cat /opt/scidesktop/manifest.d/*.json` shows the version of every part.

## Triage

| Symptom | Checks |
| --- | --- |
| "Containers are unavailable" in terminals, or tools do nothing | User namespaces are blocked for the pod: see "Platform requirements". If `unshare -U true` fails in a terminal, that confirms it; if it succeeds, the host may still refuse Apptainer's user mapping. |
| SIF files fail to mount; unpacked containers work | No `/dev/fuse` in the pod. |
| Browser stuck at "waiting for stream" | Request `/desktop/` again and read the Selkies log; check `/opt/selkies/bin/python -c 'import pixelflux, pcmflux'` succeeds. |
| sciget lists nothing | `sciget catalog list`; `~/.cache/sciget/refresh.log` for the download at start; `sciget doctor`; whether the catalog's `dir` exists under `/cvmfs`. |
| `[cvmfs] /cvmfs is empty` | The pod's CVMFS volume and mount path; whether the node or CSI mount is populated before the pod starts. |
| Internal CVMFS does not mount | The pod starts as root, has `/dev/fuse` and mount capability, an AppArmor profile that allows the mount (Docker's default profile denies it: run with `--security-opt apparmor=unconfined`), names repositories in `SCIDESKTOP_CVMFS_REPOSITORIES`, and has their config and keys under `/etc/cvmfs`. The `[cvmfs] the client said:` line in the container log has the client's own reason. |
| `/desktop/` returns an error | jupyter-server-proxy and Selkies logs; that no deployment override replaced `start.sh`. |
| Slow starts at one CPU | Give each pod at least two CPUs; a CPU limit is a quota for the whole pod, so process priority does not help. |
