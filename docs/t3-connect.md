# T3 Connect: this session's T3 Code from the T3 apps

Images with T3 Code can be reached from the T3 desktop and mobile apps
through [T3 Connect](https://t3.codes), T3's relay. It is the `t3-connect`
component, which `microdesktop`, `aidesktop` and `neurodesktop` copy beside
`t3-code` ([coding-agents.md](coding-agents.md)).

**It is off until you set it up.** A session that never sets it up runs
nothing of it and contacts nobody.

## Setting it up

1. Open `<session URL>/t3-connect/` (for example
   `https://hub.example.org/user/you/t3-connect/`). T3 Code's own **T3
   Connect** button, where its interface shows one, opens the same page.
2. Choose **Set up T3 Connect**. The page shows a code.
3. Open <https://accounts.t3.codes/device>, sign in with the account of your
   T3 app, and approve the code.
4. The page restarts T3 Code when no chat is running, waits until T3's relay
   reaches the session, and says **Ready**. In the T3 app, open Settings,
   Connections and add the environment.

**Disconnect** on the same page switches it off again. The same can be done
in a terminal with `t3 connect link --headless`, `t3 connect status` and
`t3 connect unlink`.

Approving the code gives your T3 account remote access to this session's T3
Code: its chats, its terminal and the files it can reach, which is your home
and everything else the session can read. Do not approve a code you did not
ask for.

The T3 app reaches the session only while T3 Code runs in it. T3 Code starts
when the **scigent.ai** tile is opened, and the T3 Connect page starts it
while it is open. A session nobody has opened is not reachable.

## What runs, and where it listens

| Process | When | Listens on |
| --- | --- | --- |
| the page and its API, handlers of the notebook server | always | nothing of their own; behind the notebook server's login |
| `t3 connect link --headless` | while a code is waiting for approval | nothing; it calls T3's account service |
| `cloudflared`, started by T3 Code | while T3 Code runs and a link is saved | a status port on loopback (`TUNNEL_METRICS=127.0.0.1:0`); it connects out to T3's relay |

Nothing new listens beyond loopback, linked or not. The tunnel is an
outbound connection from the session to T3's relay; a deployment that blocks
outbound traffic to `*.t3.codes` and Cloudflare blocks T3 Connect.

## What is kept private

- **The page and its API** are behind the notebook server's login. An action
  needs the page's own token as well (Jupyter's XSRF check), so another site
  cannot switch Connect on through a logged-in browser. The API accepts
  exactly four actions: `link`, `retry`, `cancel`, `disconnect`.
- **The device code** is read from the `t3` command's output and shown to the
  signed-in user only. Nothing else of that output is kept, returned or
  logged. The code is not in the container log.
- **The account's credentials** are T3's, in `~/.t3/userdata/secrets`,
  readable by the user only. The component does not read them: whether the
  relay reaches the session is the answer of `t3 connect status`, in which
  the running T3 Code checks its own tunnel.
- **T3's pairing token**, which T3 Code prints when it starts, still goes
  nowhere: T3 Code's standard output is discarded
  ([coding-agents.md](coding-agents.md#isolation)).

## How it fits T3 Code

`t3-connect` reaches `t3-code` through two extension points of that
component and changes none of its files:

| Extension point | What `t3-connect` puts there |
| --- | --- |
| `/etc/scidesktop/t3-code/environment.d/*.json`: defaults for the T3 Code server's environment | `T3CODE_CLOUDFLARED_PATH`, the relay client T3 uses, and `TUNNEL_METRICS`, which keeps that client's status port on loopback |
| `/etc/scidesktop/t3-code/connect-path`: the session's own T3 Connect page | `t3-connect/` |

Without the second file T3 Code hides its own Connect button, as before: it
signs in through t3.codes, which accepts T3's own origins only, and could
only spin here.

The relay client is `cloudflared` 2026.10.7, the upstream release executable
at `/opt/t3-connect/bin/cloudflared`, checked against its checksum. T3 would
otherwise download one into each home.

## What was not ported

neurodesktop's integration has more than this component:

- **Tailscale** (`neurodesk t3`), its other way to reach T3 Code. It needs a
  tailnet and a userspace network daemon.
- **Starting T3 Code with the session when a link is saved.** There the
  server extension owns the T3 process. Here Jupyter Server Proxy starts it
  on the first request, so a linked session is reachable once its tile, or
  the T3 Connect page, has been opened.
- **The environment's name** from the Hub user and host. T3 names the
  environment after the container's host name.
- **The tunnel-limit message.** neurodesktop reads it from T3's output, which
  is discarded here; the page says a full account is one possible cause.

## Checks

```sh
docker buildx bake t3-connect-test
./test/t3-connect-smoke.sh microdesktop
```

The component's test drives the device authorization with a stand-in for the
`t3` command: the code reaches the state, the rest of the output does not,
and Cancel ends the command. A second stand-in answers as T3 does after an
approval: Ready follows T3's own reachability check. The smoke test checks that Connect is off,
behind the login, refused from another origin, and silent in the container
log. Neither signs in to T3: linking needs an account and a person, and the
smoke test says so (`NOT TESTED`).

## Licences

`cloudflared` is Apache-2.0 (`/opt/t3-connect/LICENSE-cloudflared`). The page
and its server extension are MIT, ported from neurodesktop.
