# aidesktop

scidesktop with Intersect Australia's
[AI Ready workshop](https://github.com/IntersectAustralia/ai-ready-containers):
the workshop's notebooks and kernel, and an Airflow, MLflow and PostgreSQL of
its own in every session. It also has the
[coding agents and T3 Code](../../docs/coding-agents.md).

## Building and running

From the repository root:

```sh
docker buildx bake aidesktop          # builds scidesktop and the components, then aidesktop:latest
docker run --rm -p 8888:8888 --shm-size=2g -e JUPYTER_TOKEN=aidesktop aidesktop
./test/image-smoke.sh aidesktop       # the base's end-to-end checks and each component's
```

Open <http://localhost:8888/?token=aidesktop>.

## What is here

Only the assembly: this image is `scidesktop` (which already includes Slurm +
`jupyterlab-slurm`, VS Code, DataLad, workflow engines, VirtualGL,
`scigethelpers`, coding agents, ACP adapters,
T3 Code and T3 Connect) plus `sciget-datascience` and `ai-ready` from
`components/`. See
[docs/ai-ready.md](../../docs/ai-ready.md) for what a workshop session runs
and how to deploy it.
