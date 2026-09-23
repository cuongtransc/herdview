# Herdview

A macOS app that shows every coding agent running inside
[Herdr](https://herdr.dev), locally and on remote machines over SSH, in one
window, with a menu bar item to call that window up.

State comes from Herdr's own detection (`agent.list` on each session's socket),
never from agent hooks. See `docs/adr/` for why.

## Requirements

- macOS 13+, Swift toolchain (Xcode Command Line Tools).
- Herdr installed on every host you want to watch.
- For remote hosts: SSH access with a key that needs no passphrase prompt
  (`ssh-add` it, or use a Keychain-backed key). The app runs `ssh` itself.

## Configure

`~/.config/herdview/config.toml`:

```toml
# Optional: leave a Provider's row out of the Quota card, for one you have no
# account for. Any of: claude, codex, opencodeGo, grok. Keep it above the first
# [[hosts]] — below one, TOML reads it as a key of that host.
hidden_providers = ["codex"]

[[hosts]]
name = "local"
herdr_path = "/opt/homebrew/bin/herdr"

[[hosts]]
name = "devtuf"
ssh = "devtuf"              # ssh alias or user@host
herdr_path = "/home/cuongnb/.local/bin/herdr"
poll_seconds = 2            # optional, default 2
```

That file is written for you on a first run: with no config at all, Herdview puts
one there with a single `local` host — `herdr_path` looked for in the usual
install locations, PATH last — and starts watching this Mac. It never writes
over a config that is already there; a file that exists and does not parse is
reported in the window instead.

The app was called HerdPet and read `~/.config/herdpet/config.toml`. Nothing
migrates that file for you: move it yourself with
`mv ~/.config/herdpet ~/.config/herdview`. A config from back then may still
carry `pet`, `[clips]` or `[messages]`; those keys are ignored — there has been
no pet since `docs/adr/0003` — and the file loads as it always did. The window
position and `Keep on Top` do not survive the rename either, since they were
stored under the old bundle id.

A bar across the top counts the herd: how many agents are blocked, and quietly
how many are working or done. Below it the window lists every agent, one section
per host: the directory it is working in with its session beside it, then what
the agent calls itself, its status, and how long it has held that status. Where
an agent has no working directory the session leads instead. A row blinks for
as long as its agent is `blocked` (orange) or `done` (blue) — the two statuses
that are asking for a person — so a glance at the window answers whether
anything is waiting on you, and it keeps asking until you come. Every blinking
row pulses in step.
The list scrolls and the host headings stay put as it does. The window remembers
where you put it and how big you made it. `Keep on Top` in the Window menu
(⌘T) makes it float above other apps' windows so the herd stays readable while
you work elsewhere; it is off until you ask for it, and remembered between
launches.

A strip above the list narrows what the window shows: a search field that matches
the host, session, directory, agent kind, name and title — case- and
accent-insensitive, whitespace-separated words ANDed — beside a set of scopes
(`All`, `Needs me`, `Working`, `Idle`) whose segment counts stay live as the
text filters. ⌘F focuses the field from anywhere (Edit › Find…), and Esc clears
it. When the filter hides an agent that is asking for a person — `blocked` or
`done` — an orange banner counts how many are hidden and offers a Show button;
hosts with no match drop out, a footer says "Filter hides N agents · M hosts"
with a Clear button, and an empty match stands in as a "No agents match" notice.
The scope you pick is remembered between launches; the search text is not.
Notifications and the menu bar item are untouched — the filter only changes what
the window lists.

When an agent turns `blocked` or `done`, macOS also posts a notification: the
same directory, session and title the row shows, and clicking it brings the
window up. You are asked for permission the first time the app runs. One agent
only ever holds one notification — going `blocked`, then `done`, replaces it
rather than leaving a stack behind — and no banner is shown while Herdview is the
app in front, since the blinking row is already saying it. There is no switch for
this in the app; the switch is System Settings › Notifications › Herdview.

Above the hosts, a Quota card shows how much of each plan is used: one row per
Provider, minus anything in `hidden_providers` — a Provider you have no account
for is a row that can only ever say "not signed in". A hidden Provider is not
fetched either, so its credential file is not even read. Every Window — `5h`,
`week`, `month`, or a per-model week like `week · Fable` — shows the percent used
and how long until it
resets. A yellow tick on the bar marks how much of the Window's time has passed:
the bar is green while it stays behind the tick and turns orange once it runs past
it, being spent faster than the clock, or reaches 90%. A `month`, whose length
varies, has no tick and a grey bar until 90%. Clicking
"Quota" folds the card to one line with each Provider's shortest Window, and the
card stays folded next launch. The numbers come from each CLI's own
sign-in on this Mac, never from the remote hosts, since every host spends the
same accounts:

| Provider | Credential read |
|---|---|
| Claude | Keychain item `Claude Code-credentials` |
| Codex | `~/.codex/auth.json` |
| OpenCode Go | `opencode-go` key in `~/.local/share/opencode/auth.json` |
| Grok | `~/.grok/auth.json` |

They are only read. Herdview never refreshes a token and never runs a CLI (see
[ADR 0005](docs/adr/0005-quota-from-provider-apis-without-refresh.md)), so a
CLI you have not used for a few hours may show
"sign-in expired — run grok" with its last numbers dimmed; running that CLI
once brings it back. A CLI that is not signed in shows "not signed in". Quota
is fetched every 5 minutes, and when the window is shown, but only while the
window is visible; the ↻ button beside "Quota" fetches it at once, unless a
Provider is waiting out a rate limit. The first read of Claude's Keychain item may ask for
permission; choose Always Allow. None of these usage endpoints is documented,
so a row that says "unreadable response" means a Provider changed its API.

The menu bar item shows how many agents are `blocked`, in orange, and clicking it
shows or hides the window. Closing the window does not quit the app: the herd
keeps being polled, and the menu bar item or the Dock icon brings the window
back.

Every 30 seconds each host is asked `herdr session list --json`; every running
session is polled every `poll_seconds` with `agent.list`. Remote sessions are
reached through `ssh -N -L ~/.herdview/sock/<host>-<session>.sock:<remote socket> <host>`.

## Build and run

```bash
mise trust                     # once, so mise will load mise.toml
mise run                       # release .app → build/Herdview.app
mise run run                   # build and open
mise run test                  # swift test
mise run clean
mise run icon --color 5C43DC   # redraw scripts/AppIcon.icns (the default accent if --color is left out)
```

`CONFIG=debug mise run app` builds unoptimised. `mise run build` is the plain
compile check, without the .app around it.

Or without mise: `swift test && ./scripts/build-app.sh && open build/Herdview.app`.

Logs go to the unified log: `log stream --predicate 'process == "herdview"'`.
