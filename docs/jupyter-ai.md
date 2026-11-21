# Jupyter AI: a chat with the coding agents in JupyterLab

Every image has [Jupyter AI](https://github.com/jupyterlab/jupyter-ai): a
chat panel in JupyterLab. Choose **Chat** in the launcher, or right-click a
folder and create a chat there. A chat is a `.chat` file in that folder, and
the agent works in that folder.

Jupyter AI 3 has no model of its own. It talks to the coding agents an image
has, over the Agent Client Protocol, and each agent appears in the chat as a
persona to `@`-mention:

| Image | Personas |
| --- | --- |
| `scidesktop` | none: the chat opens and says no persona is available |
| images with the `coding-agents` component | **OpenCode** |

The agent a persona runs is the image's own (`/opt/coding-agents/bin/opencode
acp`), started for the chat as the notebook user. It uses that agent's
sign-in and configuration: what `opencode` does in a terminal, it does in the
chat. Sign in to it in a terminal first ([coding-agents.md](coding-agents.md)).

## Nothing preset

It is part of the base's Jupyter environment (`components/jupyter-env`), so
it carries no provider key, endpoint or model preset, and none can be set in
it: a model is the agent's business. An image gives its users a default
provider through the agent's own extension points
([coding-agents.md](coding-agents.md#extending-them-in-a-domain-image)).
neurodesktop does: its `neurodesk-agents` component names the Neurodesk
provider for OpenCode, and the OpenCode persona in neurodesktop's chat uses
it, with `NEURODESK_API_KEY` from the deployment.

## What is installed

`jupyter-ai` 3.2.0 from conda-forge, in the Jupyter environment's lock for
both architectures, with what it depends on: the chat (`jupyterlab-chat`),
the agent client (`jupyter-ai-acp-client`), the persona manager and router,
live documents (`jupyter-live-content`) and the notebook tools the agents
can call (`jupyter-ai-tools`, `jupyter-server-mcp`). The optional model
packages (`jupyter-ai-litellm`, Jupyternaut, the `%%ai` magics) are not
installed.

Two workarounds are applied to `jupyter-ai-acp-client` 0.3.4 at build time,
from neurodesktop (`components/jupyter-env/patches/acp_client_workarounds.py`):

- It logs every streamed chunk of a reply at `INFO`, thousands of lines per
  answer. Those four statements are demoted to `DEBUG`.
- It refuses OpenCode 2. OpenCode 2 speaks the same protocol, so the version
  check admits it.

Each is tied to the exact upstream text, and the build fails when that text
changes, so an update cannot keep or misapply a workaround silently.

## What is left out

- **Claude Code and Codex personas.** They need an adapter each
  (`claude-agent-acp`, `codex-acp`). Both are Node.js programs, and
  scidesktop has no Node.js runtime; each also installs its own copy of its
  agent. A component with a pinned Node.js and a locked `npm ci` is the way
  to add them, in images that have the agents.
- **Notebook Intelligence**, neurodesktop's other chat panel.
- **Seeding `AGENTS.md` into a chat's folder**, which neurodesktop does with a
  contents hook. The agents here read their instructions from the home
  ([coding-agents.md](coding-agents.md)).
- **neurodesktop's widget and collaboration patches.** They work around
  `jupyter-collaboration` and `jupyter-server-documents`, which Jupyter AI
  3.2 on conda-forge no longer needs.

## Checks

`components/jupyter-env`'s test checks the extensions load, are compatible
with this JupyterLab and carry the workarounds. `test/smoke.sh` checks on
every image that JupyterLab's page loads the chat extensions and the
notebook server loads theirs. Opening a chat needs a browser, and the smoke
test says so (`NOT TESTED`).

## Licences

Jupyter AI and its packages are BSD-3-Clause (Project Jupyter). The
workarounds file is MIT, from neurodesktop.
