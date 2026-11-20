# aimicrodesktop

microdesktop with Intersect Australia's
[AI Ready workshop](https://github.com/IntersectAustralia/ai-ready-containers):
the workshop's notebooks and kernel, and an Airflow, MLflow and PostgreSQL of
its own in every session.

## Building and running

From the repository root:

```sh
docker buildx bake aimicrodesktop        # builds microdesktop and ai-ready, then aimicrodesktop:latest
docker run --rm -p 8888:8888 --shm-size=2g -e JUPYTER_TOKEN=aimicrodesktop aimicrodesktop
./test/smoke.sh aimicrodesktop           # the base's end-to-end checks
./test/ai-ready-smoke.sh aimicrodesktop  # the workshop's
```

Open <http://localhost:8888/?token=aimicrodesktop>.

## What is here

Only the assembly: this image is microdesktop plus the `ai-ready` component
(`components/ai-ready`), which aidesktop copies too. See
[docs/ai-ready.md](../../docs/ai-ready.md) for what a session runs and how to
deploy it.
