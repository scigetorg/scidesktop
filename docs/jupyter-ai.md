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
| `scidesktop` and every image built on it (`microdesktop`, `datadesktop`, `dermdesktop`, `preclinicaldesktop`, `moleculardesktop`, `genomicsdesktop`, `neurodesktop`) | **OpenCode**, **Codex** and **Claude** |
| a custom image without `coding-agents` or `acp-adapters` | none (or **OpenCode** only, with `coding-agents` alone) |

The agent a persona runs is the image's own, started for the chat as the
notebook user. It uses that agent's sign-in and configuration: what `codex`,
`claude` or `opencode` does in a terminal, it does in the chat. Sign in to it
in a terminal first ([coding-agents.md](coding-agents.md)).

OpenCode speaks the protocol itself (`opencode acp`). Codex and Claude Code
need an adapter each, which the `acp-adapters` component brings
([below](#the-adapters-for-codex-and-claude-code)).

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

## The adapters for Codex and Claude Code

`acp-adapters` is included in `scidesktop` alongside `coding-agents`. It holds
`codex-acp` and `claude-agent-acp`, the programs Jupyter AI
starts for its Codex and Claude personas, at `/opt/acp-adapters`.

- **They are Node.js programs.** The component brings the Node.js release
  from nodejs.org, checked against its checksum, at
  `/opt/acp-adapters/node`. Only its interpreter is kept, nothing else uses
  it, and no `node` or `npm` command is added to `PATH`.
- **They are installed from a lock.** `npm ci` installs exactly
  `components/acp-adapters/package-lock.json`, checks each package's
  integrity hash and runs no install script.
- **They run the image's agents.** Each adapter's package would bring its
  own copy of its agent, about 250 MB each. The lock's optional packages are
  left out, and the commands point the adapters at
  `/opt/coding-agents/bin/codex` and `/opt/coding-agents/bin/claude`
  (`CODEX_PATH` and `CLAUDE_CODE_EXECUTABLE` name others). The build fails
  if a copy is installed after all.

To update an adapter, change its version in
`components/acp-adapters/package.json` and run `components/acp-adapters/lock`.
An adapter is written against a range of its agent's versions; the
component's test starts both against the agents in `coding-agents`.

## What is left out

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
notebook server loads theirs. `test/acp-adapters-smoke.sh` starts each
adapter in a session and speaks the protocol's first message to it. Opening
a chat needs a browser, and the smoke tests say so (`NOT TESTED`).

## Licences

Jupyter AI and its packages are BSD-3-Clause (Project Jupyter). The
workarounds file is MIT, from neurodesktop. The two adapters are Apache-2.0;
their dependencies' licences are in `/opt/acp-adapters/lib/node_modules`.
Node.js is MIT with the notices in `/opt/acp-adapters/node/LICENSE`.
