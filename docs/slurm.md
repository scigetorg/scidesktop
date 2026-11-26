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

It is the `slurm` component, part of the base image. The component builds
Slurm from source into `/opt/slurm`, with what the session's configuration
and external MUNGE clusters (`SLURM_CONF`) use, and links its commands into
`/usr/local/bin`. The release is `SLURM_TAG` in `docker-bake.hcl`.

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
| MariaDB and `slurmdbd` for accounting | no accounting (`accounting_storage/none`) | Slurm 25.11 runs jobs without it; `sacct` has no history. For Snakemake on this image, pass `--slurm-status-command squeue` with `--executor slurm`, and `--conda-frontend mamba` when using `--sdm conda` |
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

The queue is not started when the session runs under a user ID that does not
own and write `/run/slurm` and `/run/slurmctld` (an arbitrary non-root UID, or
`/run` mounted over). The container log says so.

## Lightcone

[Lightcone](https://github.com/LightconeResearch/lightcone-cli)'s `lc`
(lightcone-cli, with `astra-tools` and `astra-spec`) runs analyses on this
queue. It is the `lightcone` component, part of the base image, in its own
environment at `/opt/lightcone` so its Dask dependencies stay out of the
Jupyter environment. Upstream `lc` is installed unchanged; neurodesktop's
module adapter and `neurodesk-lc-materialize` are not ported.

```sh
lc compute resources                   # the shapes lc can ask the queue for
lc compute launch --cpus 2 --memory 8  # an allocation; prints its ID
lc materialize <id> baseline/answer    # builds an output on it
lc compute down <id>
```

**The catalog follows the queue.** `lc` only launches an allocation whose
CPUs and memory equal one of its catalog's offers, and Slurm fails a job
larger than the node. The queue is sized per session, so no fixed catalog
fits every session: neurodesktop's 2 CPUs and 8 GiB fail on a 4 GB container
([neurodesk/neurodesktop#1393](https://github.com/neurodesk/neurodesktop/issues/1393)).
`/usr/local/bin/lc` therefore writes a catalog from `sinfo` before it runs the
real `lc`, with two offers on the queue's default partition:

| Offer | CPUs | Memory |
| --- | --- | --- |
| `standard` | 2, or the node's if fewer | 8 GiB, or the node's if less |
| `node` | the node's | the node's; left out when it equals `standard` |

So `lc compute launch --cpus 2 --memory 8` works on any node at least that
size. The workers run `/opt/lightcone/bin/python`; an allocation runs one task
per CPU less one (at least one) and lasts 2 hours by default; local compute is
off. The file is
`${XDG_RUNTIME_DIR:-/tmp}/scidesktop-lightcone-<uid>/compute.yaml`, rewritten
at each `lc` command, in a directory only the user can write (`lc` warns and
writes nothing if the directory is anyone else's or writable by others).

**Your own catalog wins.** `lc` writes nothing and runs unchanged when
`LC_COMPUTE_CONFIG` is set, when `~/.lightcone/compute.yaml` exists, when
`sinfo` does not answer, or when `SLURM_CONF` names another cluster's
configuration: its nodes do not have this image's Python, so its catalog is
the site's to write. To keep a shape of your own, copy the generated file to
`~/.lightcone/compute.yaml` and edit it.

**No history.** The queue keeps no accounting, so once an allocation has
ended `lc compute status <id>` fails with `sacct failed`; `lc compute status`
lists only the current allocations, and an ended one is no longer among them.

## Checks

```sh
docker buildx bake slurm-test lightcone-test
./test/slurm-smoke.sh scidesktop
./test/lightcone-smoke.sh scidesktop   # lc on a 4 GB container's queue
```

## Licence

Slurm is GPL-2.0-or-later, built from unmodified upstream source (`SLURM_TAG`
in `docker-bake.hcl`), with its upstream notices (`COPYING`, `LICENSE.OpenSSL`)
and the copyright notices for its bundled libraries (`libjwt`, `jansson`,
`libb64`, `libmunge`) installed under `/opt/slurm/share/licenses/`. The start
logic and the preloaded library are this repository's.
