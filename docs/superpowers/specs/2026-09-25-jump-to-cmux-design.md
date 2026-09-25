# Jump to an Agent in cmux

Date: 2026-09-25
Status: approved

## Purpose

Double-clicking an Agent's row brings that Agent to the front: the cmux tab attached to
its Session comes forward (or a new one opens), and the Agent's pane is focused inside
Herdr. It is what `ctc herdr go` / `he` does from a terminal, done from the window that
already shows which Agent is asking for a person.

Works for every Host: local Sessions and Sessions on remote Hosts over SSH.

## Scope

In:

- Double-click on an Agent row starts a Jump.
- Hover: the row lightens and its whole title line (directory and session) turns into
  one link: accent colour, no underline (two type sizes break it in two), and a
  rounded accent chip behind it with a pointing hand while the pointer is on it — no icon; a single click on it starts a Jump. While a Jump
  runs, the title stays a link with a small spinner at its end. With no cmux, neither
  happens. (Revised 2026-09-25 after a mockup review; the first cut had no hover state.)
- Focus the Agent's pane with Herdr's `agent.focus` over the socket Herdview already
  holds for the Session (local socket, or the SSH-forwarded one for a remote Host).
- Find the cmux tab already attached to the Session and focus it; otherwise open a new
  focused tab attached to it. Then activate `cmux.app`.
- Optional top-level config key `cmux_path`.

Out:

- Terminals other than cmux (Terminal.app, iTerm, Ghostty without cmux). With no cmux, a
  Jump reports it and does nothing else.
- A configurable attach command.
- Jumping from a Notification or the menu bar item.
- Single click anywhere but the title does nothing.

## Probe (2026-09-25, `ct-hms-lan`, Session `wd-bmf`, herdr 0.9.1)

Both remote attach forms were opened in cmux tabs and inspected:

| Command | Local `ps` | tty in `cmux tree` |
|---|---|---|
| `ssh -t ct-hms-lan /home/ubuntu/.local/bin/herdr session attach wd-bmf` | yes | yes |
| `herdr --remote ct-hms-lan --session wd-bmf` | yes, plus a child `ssh -F … remote-client-bridge` on the same tty | yes |

- `herdr` is not on the remote non-interactive `PATH`; the absolute `herdr_path` is
  required. `herdr --remote` finds it itself, but needs a local herdr.
- Herdr's socket API has `agent.focus` with params `{"target": "<pane_id>"}`.

Decision: a new tab uses `ssh -t` (only ssh and the Host's own config); recognising an
existing tab accepts both forms.

## Components

### HerdviewCore (pure, unit-tested)

**`AttachClient`** — `parse(ps:)` reads `ps -axo pid=,tty=,command=` into
`(tty, sshTarget: String?, session: String)`. Lines with tty `??`/`?` are skipped.
Recognised argv:

| argv | sshTarget | session |
|---|---|---|
| `…/herdr` | nil | `default` |
| `…/herdr --session S` | nil | `S` |
| `…/herdr session attach S` | nil | `S` |
| `…/ssh [opts] T …/herdr session attach S` | `T` | `S` |
| `…/herdr --remote T [--session S]` | `T` | `S` or `default` |

`ssh` options that take a value (`-p`, `-l`, `-i`, `-o`, `-F`, `-J`, `-S`, …) are skipped
with their value, so `T` is the first non-option argument. An `ssh` whose remote command
is not `<herdr> session attach S` (the `remote-client-bridge` child, the forward
`ssh -N -L …`, a plain shell) is not a client. Every other `herdr` invocation (server,
API calls) is not a client.

**`CmuxLayout`** — `parse(tree:)` reads `cmux tree --all --json` into terminal surfaces
`(ref, tty, workspaceRef, windowRef)` and the active window/workspace/pane. Surfaces
without a tty are skipped. cmux prints bare tty names (`ttys017`); `ps` does too.

**`Jump.route(host:session:clients:layout:)`** returns:

- `.focus(surface)` — a client on this Host and Session sits on a surface's tty. A local
  Host matches clients with `sshTarget == nil`; a remote Host matches
  `sshTarget == host.ssh` exactly. With several, the one in the active window wins, else
  the first.
- `.open` — no such tab.

**`HostCommand.attach(host:session:)`** — local: `<herdr_path> session attach S`;
remote: `/usr/bin/ssh -t <ssh> <herdr_path> session attach S`. Rendered as one
shell-quoted string for `cmux new-surface --command`.

**`HerdrClient.agentFocus(socketPath:paneId:)`** — sends `agent.focus` with
`{"target": paneId}` and checks for a success response.

**Config** — `cmux_path` (optional, top level, above the first `[[hosts]]`). Unset:
first executable of `/opt/homebrew/bin/cmux`, `/usr/local/bin/cmux`,
`/Applications/cmux.app/Contents/Resources/bin/cmux`.

### App

**`SessionJumper`** — owns one in-flight Jump; a double-click while one runs is ignored.
Off the main thread:

1. `agent.focus` on the Session's socket. A failure is logged and the Jump continues —
   landing in the Session beats landing nowhere.
2. Run `ps` and `cmux tree --all --json` (5 s timeout each, via `ProcessRunner`).
3. Route; run `cmux focus-panel --panel R --workspace W --window N`, or
   `cmux new-surface --type terminal --focus true --command <attach>` with the active
   window/workspace/pane when known.
4. Activate `cmux.app`.

**`AgentListView`** — the Agent row gets a double-click gesture that calls the jumper,
a hover state that lightens it and turns the title line into one `Button` link. The tooltip is unchanged: the hover
state is the hint. `AgentStore` carries
`canJump` and `jumpingKey` for it.

## Errors

Shown with the existing `Notice` at the top of the list, cleared after ~5 s or on the
next Jump:

| Case | Notice |
|---|---|
| no cmux found | `cmux not found — set cmux_path in config.toml` |
| cmux exits non-zero / times out | `cmux <command>: <last stderr line>` |
| `ps` fails | treated as no clients → a new tab opens |

A Session that stopped, or an SSH prompt (passphrase, host key), shows up inside the new
tab, where the person can answer it; Herdview does not report it.

## Testing

Unit (`Tests/HerdviewCoreTests`):

- `AttachClientTests` — fixtures from the probe's real `ps` lines: both remote forms
  parse; the `remote-client-bridge` child, `ssh -N -L` forward, herdr server and `??`
  tty lines are skipped; `ssh -p 22 -o X=Y T …` finds `T`; no `--session` → `default`.
- `CmuxLayoutTests` — surfaces with and without tty; active refs; malformed JSON throws.
- `JumpRouteTests` — local match, remote match by `ssh` target, same session name on
  another Host does not match, several tabs prefer the active window, no tab → `.open`.
- `HostCommandTests` — `attach` for local and remote, quoting of a session name with a
  space.
- `HerdrProtocolTests` — `agent.focus` request line.

Manual: add `ct-hms-lan` to the config; double-click a local Agent and a `ct-hms-lan`
Agent — first time opens a tab, second time focuses the same tab; with `cmux_path`
pointing nowhere, the Notice shows.

Gate: `mise run ci`.
