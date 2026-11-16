# Scidesktop operator runbook

This runbook deploys scidesktop as a JupyterHub single-user image. Use an image
digest or an immutable short-SHA tag from `ghcr.io/scigetorg/scidesktop`; do not
deploy `latest` when reproducibility matters.

## JupyterHub configuration

Allocate at least two CPUs and 2 GiB of shared memory. The example uses
KubeSpawner with an externally managed CVMFS mount:

```python
c.KubeSpawner.image = "ghcr.io/scigetorg/scidesktop:<short-sha>"
c.KubeSpawner.cpu_guarantee = 2
c.KubeSpawner.cpu_limit = 2

c.KubeSpawner.environment = {
    "SCIDESKTOP_APPTAINER_SETUID": "auto",
    "SCIDESKTOP_CVMFS_MODE": "external",
}

c.KubeSpawner.volumes = [
    {
        "name": "shm",
        "emptyDir": {"medium": "Memory", "sizeLimit": "2Gi"},
    },
    {
        "name": "cvmfs",
        # Replace this with the cluster's PVC, CSI or hostPath definition.
        "persistentVolumeClaim": {"claimName": "cvmfs"},
    },
]
c.KubeSpawner.volume_mounts = [
    {"name": "shm", "mountPath": "/dev/shm"},
    {"name": "cvmfs", "mountPath": "/cvmfs", "readOnly": True},
]
```

Do not set `c.KubeSpawner.cmd`, `command` or `args` merely to start Jupyter.
The image deliberately keeps docker-stacks' `start.sh`; it accepts the
spawner-supplied command and handles user setup. Only Jupyter listens outside
the container on port 8888. The desktop is created lazily when the user opens
the **Desktop** launcher.

If `auto` selects the setuid Apptainer starter, the pod security policy must
permit that binary to elevate. If the cluster grants unprivileged user
namespaces, `auto` disables the setuid path. Validate the selected path in the
pod startup log and against the cluster's security policy.

## Environment contract

| Variable | Default | Meaning |
| --- | --- | --- |
| `SCIDESKTOP_APPTAINER_SETUID` | `auto` | `auto` probes user namespaces as the notebook user; `yes` requests the setuid starter; `no` disables it. |
| `SCIDESKTOP_CVMFS_MODE` | `external` | `external` consumes an existing `/cvmfs`; `internal` mounts with FUSE; `disabled` skips CVMFS setup. |
| `SCIDESKTOP_CVMFS_REPOSITORIES` | empty | Comma-separated repositories to mount in `internal` mode. |
| `CVMFS_HTTP_PROXY` | `DIRECT` | Proxy written to CVMFS configuration in `internal` mode. |
| `CVMFS_QUOTA_LIMIT` | `5000` | CVMFS cache quota in MiB in `internal` mode. |
| `CVMFS_CACHE_BASE` | `/var/lib/cvmfs` | Cache directory in `internal` mode; mount persistent storage here if desired. |

`external` is the normal JupyterHub mode: arrange `/cvmfs` with the cluster's
CVMFS CSI integration, a read-only host mount or another cluster-supported
volume. `internal` requires root at startup, `/dev/fuse`, mount capability,
repository configuration and public keys under `/etc/cvmfs`; it is unsuitable
for most restricted clusters. Derived images supply their own repository
configuration, keys and sciget catalogue—the base image intentionally ships
none.

At one CPU, overlapping startup work has measured 13.9 seconds instead of 4.7
seconds when staged. Process priority does not help because a Kubernetes CPU
limit is a quota for the entire cgroup. Give each single-user pod at least two
CPUs rather than tuning process priority.

## Deployment check

1. Start a single-user server and inspect its logs for `[apptainer]` and
   `[cvmfs]`. Confirm the decisions match the pod security and volume setup.
2. Open JupyterLab on port 8888, then open **Desktop** from the launcher.
3. Confirm the LXQt desktop renders and an application tile from the derived
   image appears and starts.
4. In a terminal, run `apptainer --version`, `cvmfs2 --version`, and
   `grep '^allow setuid' /opt/apptainer/etc/apptainer/apptainer.conf`.

## Triage

| Symptom | Checks |
| --- | --- |
| Browser remains at “waiting for stream” | Run `/usr/bin/python3 -c 'import pixelflux, pcmflux'` in the pod. An import failure usually means an encoder runtime library is missing; inspect the Selkies log after requesting `/desktop/`. |
| Application tiles do nothing | Check `allow setuid` in `apptainer.conf`, the `[apptainer]` startup decision, whether the runtime grants unprivileged user namespaces, and whether pod security permits the setuid starter. Run the launch command from a terminal to expose its error. |
| Application menu is empty | Confirm the derived image installed a sciget catalogue and launchers under `/opt/sciget/applications`; check that `/opt/sciget` is present in `XDG_DATA_DIRS`, and verify the required repository is visible below `/cvmfs`. |
| `[cvmfs] /cvmfs is empty` | Check the pod volume and mount path, then verify the node/CSI mount is populated before starting the single-user pod. |
| Internal CVMFS does not mount | Confirm the pod starts as root, has `/dev/fuse` and mount capability, names repositories in `SCIDESKTOP_CVMFS_REPOSITORIES`, and contains their config and public keys under `/etc/cvmfs`. |
| Desktop route returns an error | Inspect the Jupyter server-proxy and Selkies logs. Confirm no deployment override replaced `start.sh` and that only Jupyter port 8888 is exposed. |
