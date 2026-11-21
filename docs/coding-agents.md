# Coding agents and T3 Code

`microdesktop` and `aidesktop` come with three command-line
coding agents and a browser interface for them. The base image, `scidesktop`,
has neither. They are two optional components
(see [images.md](images.md#optional-components)):

| Component | What it adds | Where |
| --- | --- | --- |
| `coding-agents` | [Codex](https://github.com/openai/codex), [Claude Code](https://code.claude.com/docs) and [OpenCode](https://opencode.ai) for terminals | `/opt/coding-agents`, commands `codex`, `claude`, `opencode` |
| `t3-code` | [T3 Code](https://github.com/pingdotgg/t3code), opened from the **scigent.ai** launcher tile | `/opt/t3-code`, command `t3` |

`t3-code` works without `coding-agents`, but then it has no agent to drive
until the user installs one.

## Using the agents

Open a terminal and run `codex`, `claude` or `opencode`. Each asks you to sign
in to its provider the first time. The image presets no provider, model,
endpoint or key, and makes no request to a model on its own.

What an agent stores (its sign-in, settings and history) is in your home:
`~/.codex`, `~/.claude` and `~/.claude.json`, `~/.config/opencode` and
`~/.local/share/opencode`. Treat these folders as private.

A new home gets one settings file per agent, each with one setting that turns
off the agent's self-update: the binaries belong to the image, and a newer
image brings newer agents. The files are yours to edit. They are copied only
when missing, so your changes survive restarts and image updates.

## Using T3 Code

Choose **scigent.ai** in JupyterLab's launcher. T3 Code opens in a JupyterLab
tab. It is also at `<session URL>/t3-code/` in a browser tab of its own.

T3 Code starts when it is first opened, not with the session. The first page
appears after about four seconds and shows "T3 Code is starting" until then.
A session that never opens the tile runs no T3 process.

T3 Code drives the agents installed in the image. Sign in to an agent in a
terminal first, or in T3 Code's provider settings, where each agent can also
be turned on or off.

**T3 Connect** (using this session's T3 Code from the T3 desktop or mobile
app, through T3's relay) is the `t3-connect` component, which the images
that have T3 Code copy too. It is off until the user sets it up; see
[t3-connect.md](t3-connect.md).

## What runs

| Process | Listens on | Reached at |
| --- | --- | --- |
| T3 Code server (`/opt/t3-code/app/t3`), from the first use of the tile | `127.0.0.1`, a port the proxy picks | `<session URL>/t3-code/` |
| the agents T3 Code or a terminal starts | nothing | |

Jupyter Server Proxy starts the server with `/opt/t3-code/lib/t3_code_serve.py`
and stops it when the notebook server stops. T3 then removes its runtime file
and closes its database; this took under a second when measured.

## Isolation

T3 Code listens on loopback only. Jupyter Server Proxy is the only way to it,
and it checks the notebook server's login on every request, page, API call and
WebSocket alike. Behind JupyterHub that is the Hub's login for this user's
server.

T3 has its own sessions as well. The browser never holds one:

- When the server starts, `t3_code_serve.py` issues a T3 session for the proxy
  and stores its token in `~/.t3/jupyter-proxy-session.json`, readable by the
  user only. The session from the previous start is revoked.
- The proxy adds that token to each request after the notebook server has
  accepted it, and drops the notebook server's own cookies and token before
  forwarding. T3 sets no cookie; a `Set-Cookie` or cross-origin header from T3
  would be removed.
- T3 prints a pairing token when it starts. It goes nowhere: T3's standard
  output is discarded, so the token is not in the container log.
- A request that changes something (anything but `GET`, `HEAD` and
  `OPTIONS`) gets the token only when it names the session's own origin, or
  one the notebook server is configured to allow, as Jupyter requires of a
  WebSocket. Jupyter Server Proxy leaves that check to the proxied
  application, and T3 has none: without it, a page on another site could have
  the browser send its Hub cookie with a request that T3 then accepts. A
  client that sends the notebook server's token is not held to it.
- T3's client puts a short-lived ticket in its WebSocket URL, and the proxy
  logs the URLs it connects to. The ticket is replaced by `[redacted]` in
  the notebook server's log.

Do not expose T3's port through a Service or an ingress.

T3 Code's telemetry is off unless `T3CODE_TELEMETRY_ENABLED` is set.

## Persistence

Everything T3 Code keeps is in `~/.t3`: its database, settings, worktrees,
logs and secrets. The folder is created private to the user (mode `0700`).

- Deleting `~/.t3` resets T3 Code. The next start creates it again.
- Use one session per home at a time. Two T3 servers on the same `~/.t3`
  would share one database.
- T3 migrates its database when a newer version first opens it. An older T3
  may not open it again.

## Behind the session's URL

T3's web client has no base-path option: it addresses its server from the root
of the origin. `/opt/t3-code/lib/t3_code_proxy.py` adapts it on the way
through the proxy. It prefixes the page's own URLs, bases the client's router
at `<session URL>/t3-code`, and adds a small script
(`t3_code_adapter.js`) that sends the client's `fetch` and `WebSocket` calls
to the same place. Nothing in `/opt/t3-code/app` is modified.

The adapter rewrites three anchors in three script bundles. It is tied to the
web client of the pinned release, and fails rather than guesses: a request for
a bundle whose anchor moved answers 500. The component's test runs the adapter
over every file of the installed client, so a T3 update that moves an anchor
fails the build, not a session.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `T3_CODE_WORKDIR` | the home folder | The folder T3 Code starts in and offers for new projects |
| `T3CODE_HOME` | `~/.t3` | T3's data directory (T3's own variable) |
| `T3CODE_TELEMETRY_ENABLED` | `false` | T3's telemetry (T3's own variable) |
| `T3CODE_LOG_LEVEL` | `Warn` | What T3 writes to the notebook server's log (T3's own variable) |
| `JUPYTERHUB_SERVICE_PREFIX` | `/` | Set by JupyterHub. T3 Code is served below it |

No `cmd` or extra port is needed in a JupyterHub profile. Everything in the
[operator runbook](operator-runbook.md) applies as for scidesktop.

**Sizing.** The two components add 1.3 GB to an image: 0.9 GB for the three
agents and 0.4 GB for T3 Code. An idle T3 Code server holds about 400 MB of
memory once opened, and each running agent adds its own.

## Extending them in a domain image

These components carry no community's defaults. An image that has some
supplies them through the same places, without changing a component:

| To set | Put |
| --- | --- |
| an agent's default settings (a provider, an MCP server, instructions) | the file at its home path under `/etc/scidesktop/home-defaults/`, for example `.codex/AGENTS.md`, `.claude/CLAUDE.md`, `.config/opencode/AGENTS.md`. An image's own Dockerfile may also replace one of the three settings files this component ships: the image's layer wins. Another component may not (rule L1) |
| an OpenCode provider or MCP server, from a component | a JSON file of its own, and a start hook in `/usr/local/bin/before-notebook.d/` that sets `OPENCODE_CONFIG` to it. OpenCode merges that file with the user's `~/.config/opencode/opencode.json` |
| Defaults for the T3 Code server's environment | a JSON file of variable names and values in `/etc/scidesktop/t3-code/environment.d/`. A variable the deployment set is kept. `t3-connect` names T3's relay client there |
| T3 Code's default settings (provider instances, binary paths) | a JSON file in `/etc/scidesktop/t3-code/settings.d/`. The files are merged in name order into the user's `~/.t3/userdata/settings.json` when T3 starts. They only fill gaps: a value already in the user's file is never changed, at any depth |
| environment for T3 Code and the agents it starts | `ENV` in the image's Dockerfile, or a start hook in `/usr/local/bin/before-notebook.d/` |

`T3CODE_*` variables set in the image reach T3, except where it listens
(`T3CODE_HOST`, `T3CODE_PORT`, `T3CODE_LAN`): the proxy decides that.

## What is left out

The components were ported from
[neurodesktop](https://github.com/neurodesk/neurodesktop). These parts of its
integration were not:

- **Tailscale.** T3 Connect and its relay client are the `t3-connect`
  component ([t3-connect.md](t3-connect.md)). neurodesktop's other way to
  reach T3 Code, through a tailnet, is not here.
- **Neurodesk's defaults** are not in these components. The `neurodesktop`
  image gets its instructions and model provider from the `neurodesk-agents`
  component, through the extension points above
  ([neurodesktop.md](neurodesktop.md#coding-agents)). The provider wrappers
  and the MCP server, which needs a personal token, were not ported.
- **The launcher extension.** The tile is a Jupyter Server Proxy launcher
  entry. Links in T3's chat do not open files in JupyterLab, and there is no
  retry dialog: if T3 exits, the next request starts it again.
- **The Jupyter AI agent adapters** (`codex-acp`, `claude-agent-acp`).
  Jupyter AI is in every image and OpenCode appears in its chat without an
  adapter. The two adapters need Node.js; see
  [jupyter-ai.md](jupyter-ai.md#what-is-left-out).
- **Node.js.** Every binary here is self-contained, so no runtime is added.

## Updating

Versions and checksums are in `docker-bake.hcl`; Renovate proposes new
versions. A version bump fails the build until both checksums of that tool are
updated:

| Tool | Where the checksums come from |
| --- | --- |
| Codex | the `sha256` digests of `codex-{x86_64,aarch64}-unknown-linux-musl.tar.gz` on the GitHub release `rust-v<version>` |
| Claude Code | `platforms.linux-{x64,arm64}.checksum` in `https://downloads.claude.ai/claude-code-releases/<version>/manifest.json` |
| OpenCode | `sha256sum` of `https://registry.npmjs.org/@opencode/cli-linux-{x64,arm64}/-/cli-linux-{x64,arm64}-<version>.tgz` |
| T3 Code | the `sha256` digests of `t3-<version>-linux-{x64,arm64}.tar.gz` on the GitHub release `v<version>` |

Check an image with:

```sh
docker buildx bake microdesktop coding-agents-test t3-code-test
./test/image-smoke.sh microdesktop
```

A T3 Code update whose web client moved an anchor fails `t3-code-test` with
the anchor's name. Find the new spelling in the bundle under
`/opt/t3-code/app/client/assets` and update the anchor in `t3_code_proxy.py`.
T3 Code 0.1.5 is pinned because 0.1.10, the newest release at the time of
writing, has already moved one.

## Licences

The images redistribute these binaries unmodified. Each comes with its licence
or notice in the image.

| Tool | Licence | In the image |
| --- | --- | --- |
| Codex | Apache-2.0 | `/opt/coding-agents/licenses/codex-LICENSE`, `codex-NOTICE` |
| OpenCode | MIT | `/opt/coding-agents/licenses/opencode-LICENSE` |
| Claude Code | proprietary: "© Anthropic PBC. All rights reserved. Use is subject to Anthropic's Commercial Terms of Service" | `/opt/coding-agents/licenses/claude-code-LICENSE.md` |
| T3 Code | MIT; its bundled packages are listed with their licences | `/opt/t3-code/app/LICENSE`, `/opt/t3-code/app/client/third-party-licenses.json` |
| the tile's icon | BSD-3-Clause (JupyterLab's code icon) | `/opt/t3-code/lib/scigent.svg` |

Claude Code is not open source and its terms grant no redistribution right in
so many words. The image carries Anthropic's own release binary, unmodified
and with its notice. To build without it, remove its stage from
`components/coding-agents/Dockerfile`.
