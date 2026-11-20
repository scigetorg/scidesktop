"""The AI Ready landing page, served by the notebook server at <base_url>ai-ready/."""

from jupyter_server.base.handlers import JupyterHandler
from tornado.web import authenticated


class AiReadyDashboard(JupyterHandler):
    @authenticated
    def get(self):
        self.finish(self.render_template("ai_ready_dashboard.html"))


default_handlers = [(r"/ai-ready/?", AiReadyDashboard)]
