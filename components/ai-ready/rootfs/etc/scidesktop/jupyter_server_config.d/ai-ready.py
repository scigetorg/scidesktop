# AI Ready's part of the notebook server's configuration: the Airflow and
# MLflow tiles, the workshop page, and the wait for the services at shutdown.
import sys

# The dashboard handler and the service definitions; Jupyter imports them
# from here without a PYTHONPATH that kernels would inherit.
for _dir in ("/opt/scidesktop", "/opt/ai-ready/lib"):
    if _dir not in sys.path:
        sys.path.append(_dir)
from ai_ready_services import AIRFLOW_PORT, MLFLOW_PORT  # noqa: E402
from stop_supervisor import register_supervisor_shutdown  # noqa: E402

# Airflow and MLflow listen on loopback only. The proxy checks the notebook
# server's login before it forwards a request, Airflow's admin UI included.
# update() adds to the entries of other components.
c.ServerProxy.servers.update({  # noqa: F821
    name: {
        "port": port,
        # Both serve under the session's own path, so the proxy keeps it.
        "absolute_url": True,
        "launcher_entry": {
            "enabled": True,
            "title": title,
            "icon_path": f"/opt/ai-ready/upstream/icons/{name}.svg",
            "category": "AI Ready",
        },
    }
    for name, title, port in (("airflow", "Airflow", AIRFLOW_PORT), ("mlflow", "MLflow", MLFLOW_PORT))
})
c.ServerApp.extra_services.append("ai_ready_dashboard")  # noqa: F821
c.ServerApp.extra_template_paths.append("/opt/ai-ready/lib")  # noqa: F821
c.ServerApp.default_url = "/ai-ready/"  # noqa: F821
c.LabApp.default_url = "/ai-ready/"  # noqa: F821

# Set by the start hook (40-ai-ready.sh); removed here so kernels and
# terminals do not inherit it.
register_supervisor_shutdown("AI_READY_SUPERVISOR_PID", "ai_ready_services.py", seconds=30)
