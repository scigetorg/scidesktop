# Slurm: a queue in every session

Every image starts a [Slurm](https://slurm.schedmd.com) queue for the session:
one controller and one worker, for this container alone. `sbatch`, `srun`,
`squeue`, `scancel` and `sinfo` work in any terminal, so a workflow written
for a cluster runs unchanged, and tools that submit Slurm jobs have something
to submit to.

```sh
sinfo                                  # one node, the size of the session
sbatch --cpus-per-task=2 analysis.sh   # runs in the background, output in slurm-<job>.out
squeue                                 # what is queued and running
srun --pty bash                        # an interactive step
```

It is the `slurm` component, part of the base image. Slurm itself is the OS
layer's packages (`components/os-ubuntu/packages/slurm.txt`); the component
is what runs it.

## What runs

| Process | Runs as | Listens on |
| --- | --- | --- |
| `slurm-session run`, the supervisor | the notebook user | nothing |
| `slurmctld`, the controller | the notebook user | `127.0.0.1:6817`, a socket in `/run/slurmctld` |
| `slurmd`, the worker | the notebook user | `127.0.0.1:6818`, a socket in `/run/slurm` |

The start hook `50-slurm.sh` starts the supervisor beside the notebook
server. The queue is ready a few seconds later;
`/opt/slurm/bin/slurm-session wait` returns when it is.

**Size.** One partition, `scidesktop`, with one node. Its CPUs are the
container's CPU limit (rounded up), its memory the container's memory limit
less 512 MB for the notebook server and desktop. Both come from `CPU_LIMIT`
and `MEM_LIMIT`, which KubeSpawner sets or the `startup` component reads from
the cgroup. Without limits the node is the machine.

**Jobs** run as the notebook user, in the session's container, with the
environment `sbatch` was called from. They see the same home, modules and
containers as a terminal.

## No privileges

neurodesktop starts its Slurm as root: `munged`, MariaDB, `slurmdbd`,
`slurmctld` and `slurmd`, each under its own system user. A session without
root or passwordless `sudo` gets no queue there. scidesktop sessions run as
the notebook user with no capability, as JupyterHub pods do, so this
component needs none:

| neurodesktop | Here | Why |
| --- | --- | --- |
| `munged` for authentication | Slurm's own `auth/slurm` with a key generated at each start, private to the user | no daemon, no system user |
| MariaDB and `slurmdbd` for accounting | no accounting (`accounting_storage/none`) | Slurm 25.11 runs jobs without it; `sacct` has no history |
| `slurmctld` and `slurmd` as root and `slurm` | both as the notebook user (`SlurmUser`, `SlurmdUser`) | a worker that is not root can only run its own user's jobs, which is the only user there is |
| cgroup confinement, when the container allows it | none (`CgroupPlugin=disabled`) | cgroups need root. The container's own limits still bound everything |
| a patched `slurmd` for `--get-user-env` | not offered | reading a login environment needs `su`, which needs root. Jobs inherit the submitting environment |
| listening on every interface | loopback only | see below |

The smoke test runs the queue in a container with no capability at all
(`CapEff` is zero) and submits a job.

## Loopback only

Slurm has no setting for the address its daemons listen on. They bind every
interface, or with `NoInAddrAny` the address the host name resolves to, which
in a pod is the address other pods reach it at. The supervisor starts both
daemons with a 40-line library preloaded (`/opt/slurm/lib/loopback_bind.so`,
source in `components/slurm/src`) that turns a bind to every interface into a
bind to loopback. Jobs do not inherit it.

`srun` opens ports of its own for a step's input and output, for as long as
the step runs. Those are opened by the command, not the daemons, and are on
every interface; every message on them is authenticated with the session's
key. The smoke test checks that an idle session listens beyond loopback on
8888 only.

## State

Everything is under `/run/slurm`, which the image gives to the notebook
user: the generated `slurm.conf` and key (`conf/`), the controller's state,
the worker's spool and the logs (`log/slurmctld.log`, `log/slurmd.log`).
`/etc/slurm/slurm.conf` is a link to the generated file, so the commands
need no `SLURM_CONF`. None of it is in the home and none of it outlives the
container: a job would not either. A restarted container starts an empty
queue.

## Stopping

When the container stops, the supervisor stops the worker, which ends
running jobs, then the controller. The notebook server waits for it, also
when the server exits on its own. This took under a second when measured; a
daemon that does not stop within 20 seconds is killed.

If a daemon exits, the supervisor stops the other and says so in the
container log. The session goes on without a queue.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `SCIDESKTOP_SLURM` | `yes` | `no` starts no queue |
| `SCIDESKTOP_SLURM_PARTITION` | `scidesktop` | the partition's name |
| `SCIDESKTOP_SLURM_MEMORY_RESERVE_MB` | `512` | memory kept back from jobs |
| `SCIDESKTOP_SLURM_PORTS` | `6817,6818` | the controller's and the worker's loopback ports |
| `SLURM_CONF` | unset | set to a cluster's configuration (an HPC login node, with its sockets mounted): that cluster is used and none is started |

The queue is not started when the session runs under a user ID that cannot
write `/run/slurm` (an arbitrary UID, or `/run` mounted over). The container
log says so.

## Checks

```sh
docker buildx bake slurm-test
./test/slurm-smoke.sh scidesktop
```

## Licence

Slurm is GPL-2.0-or-later, installed from Ubuntu's packages, unmodified. The
start logic and the preloaded library are this repository's.
