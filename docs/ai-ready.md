# AI Ready: the workshop image

`datadesktop` adds Intersect Australia's
[AI Ready workshop](https://github.com/IntersectAustralia/ai-ready-containers)
to scidesktop. Every session runs its own Airflow, MLflow and
PostgreSQL beside JupyterLab and the desktop. All of it comes from one
component, `components/ai-ready`, which the image copies
(see [images.md](images.md#optional-components)).

## Using a session

A session opens JupyterLab. Its launcher has **Airflow** and **MLflow** tiles
under **AI Ready**, beside the desktop's. The **AI Ready Workshop** page at
`<session>/ai-ready/` links JupyterLab, Airflow, MLflow and the desktop; each
opens in a new browser tab.

Airflow and MLflow start in the background and are ready about half a minute
after the session. Until then their pages show an error; reload them.

The workshop's files are in `~/ai-ready`:

| Folder | Content |
| --- | --- |
| `notebooks` | the workshop notebooks |
| `dags` | the Airflow pipelines; Airflow reads this folder |
| `src` | Python code the notebooks and pipelines share |
| `datasets` | the data they use |

A file is copied there at start only when it is missing, so your edits survive
restarts and image updates. To get the original of a file back, delete it and
restart the session.

The notebooks open with the **AI Ready (Python 3.12)** kernel, which has the
workshop's libraries. It can import the code in `~/ai-ready/src` from any
folder. `MLFLOW_TRACKING_URI` is set in notebooks and terminals, so runs go to
the session's own MLflow. The kernel's environment (`/opt/ai-ready/env`) is
part of the image and read-only. For other libraries, create your own
environment as the [README](../README.md) shows.

## What runs

| Service | Listens on | Reached at |
| --- | --- | --- |
| Airflow API server and UI | `127.0.0.1:8080` | `<session URL>/airflow/` |
| Airflow scheduler, DAG processor, triggerer | nothing | through the Airflow UI |
| MLflow tracking server | `127.0.0.1:5000` | `<session URL>/mlflow/` |
| PostgreSQL 15 | `127.0.0.1:5432` | by Airflow and MLflow only |

Airflow runs in its own Python environment (`/opt/ai-ready/airflow`), apart
from the notebook libraries. It runs one task at a time and one active run per
DAG, which bounds the memory the background services use. MLflow's job workers
(GenAI evaluation) are off for the same reason.

A supervisor starts the services from the start hook `40-ai-ready.sh` and logs
to the container log with the prefix `[ai-ready]`.

## Isolation

The services listen on loopback only. Jupyter Server Proxy is the only way to
them, and it checks the notebook server's login first. Airflow's all-admins
mode therefore gives the session's owner, and nobody else, control of their
own Airflow. There is no shared workshop password and no shared database: the
database password and Airflow's keys are generated in each home at first start.

Do not expose ports 8080, 5000 or 5432 through a Service or an ingress.

## Persistence

Everything the services keep is in `~/.ai-ready`: the PostgreSQL data, Airflow's
state and logs, MLflow's artifacts and the generated credentials
(`credentials.json`, readable by the user only). Treat the folder as private
application data.

- Deleting `~/.ai-ready` resets Airflow and MLflow. The next start creates it
  again.
- Back up the whole home to keep the database and its credentials together.
- Use one session per home at a time. Two sessions on the same home would run
  two PostgreSQL servers on one data directory.
- The data directory belongs to PostgreSQL 15. A later major version cannot
  open it, so the component stays on 15 until a migration is written.

Each start migrates the Airflow database. The workshop's Airflow variables are
imported once; later starts keep what the user changed in the Airflow UI.

## Stopping and failures

When the container stops, the supervisor stops Airflow and MLflow first, then
PostgreSQL, and the notebook server waits for it. This took 3 to 8 seconds
when measured and is capped at 25. Kubernetes' default grace period of 30 seconds
is enough. Docker's default is 10 seconds; use `docker stop --time 40` to be
safe. A container that is killed instead loses nothing committed: PostgreSQL
recovers at the next start.

If a service exits, the supervisor stops the others and ends the notebook
server, so the failure shows in the container log and a restart brings
everything back. The log line starts with `[ai-ready] FAILED`. In a container
started as root the supervisor cannot end the notebook server; it logs that the
session needs a restart.

## Deploying

```python
c.KubeSpawner.image = "ghcr.io/scigetorg/datadesktop:<short-sha>"
c.KubeSpawner.environment = {"AI_READY_PUBLIC_ORIGIN": "https://hub.example.org"}
```

No `cmd` is needed: the image's own start command runs the services. Everything
in the [operator runbook](operator-runbook.md) applies as for scidesktop.

| Variable | Default | Purpose |
| --- | --- | --- |
| `AI_READY_PUBLIC_ORIGIN` | `http://127.0.0.1:8888` | The origin (scheme, host and port) users reach the Hub at. Airflow builds its links from it. MLflow accepts requests for this host only, and a browser's changes from this origin only: with the wrong value its pages load and saving in them fails with 403. |
| `JUPYTERHUB_SERVICE_PREFIX` | `/` | Set by JupyterHub. The services serve under this path. |

**Sizing.** CI tests a session at 2 CPUs and 4 GB, where the workshop's training
pipeline takes about two minutes. Limits are for the whole session, background
services included: idle, they hold about 1.1 GB. 8 GB and 4 CPUs leave room to train in a pipeline while
working in JupyterLab.

**Publishing.** CI publishes `ghcr.io/scigetorg/datadesktop` for amd64 and
arm64, tagged as scidesktop is, and mirrors newly published builds to
`quay.io/scigetorg/datadesktop` when `QUAY_ORG` is configured
(see [images.md](images.md#ci-and-publishing)). Any tag that has successfully
mirrored can be pulled from either registry for `c.KubeSpawner.image` (older
GHCR tags are not backfilled). A new GHCR package starts private: make it
public or give the cluster a pull secret.

## Updating the workshop

The workshop's notebooks, pipelines and requirements come from one commit of the
upstream repository, `AI_READY_COMMIT` in `docker-bake.hcl`. Renovate proposes
new commits. After changing it, or a pin in `components/ai-ready`, run:

```sh
components/ai-ready/lock
```

The build refuses locks made for another commit. `prepare.py` in the component
makes two changes to the upstream content: it adds a model type to the
workshop's skops allow-list, and it points the notebooks at the `ai-ready`
kernel. It fails the build if upstream changes the code it patches.

Check an image with:

```sh
docker buildx bake datadesktop ai-ready-test
./test/image-smoke.sh datadesktop      # every check, or only the workshop's:
./test/ai-ready-smoke.sh datadesktop
```

The locks cover both architectures: a conda lock each, and pip locks whose
every package has an x86_64 and an aarch64 wheel. The build installs wheels
only, so a package without one fails the build on that architecture.
