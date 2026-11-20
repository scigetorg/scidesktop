# aidesktop

scidesktop with Intersect Australia's
[AI Ready workshop](https://github.com/IntersectAustralia/ai-ready-containers):
the workshop's notebooks and kernel, and an Airflow, MLflow and PostgreSQL of
its own in every session.

## Building and running

From the repository root:

```sh
docker buildx bake aidesktop          # builds scidesktop and ai-ready, then aidesktop:latest
docker run --rm -p 8888:8888 --shm-size=2g -e JUPYTER_TOKEN=aidesktop aidesktop
./test/smoke.sh aidesktop             # the base's end-to-end checks
./test/ai-ready-smoke.sh aidesktop    # the workshop's
```

Open <http://localhost:8888/?token=aidesktop>.

## What is here

Only the assembly: this image is scidesktop plus the `ai-ready` component
(`components/ai-ready`), which aimicrodesktop copies too. See
[docs/ai-ready.md](../../docs/ai-ready.md) for what a session runs and how to
deploy it.
