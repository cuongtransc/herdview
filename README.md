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
# cmux_path = "/opt/homebrew/bin/cmux"   # optional; where cmux is

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

Point at an agent's row and its title — directory and session — turns into a link: click it, or
double-click anywhere on the row, to jump to the agent in [cmux](https://cmux.dev): its pane is
focused inside Herdr, and the cmux tab attached to its session comes forward. With
no such tab, a new one opens running `herdr session attach <session>` — over
`ssh -t <ssh>` for a remote host. A tab counts as attached to a remote session when
its command names the host's `ssh` value exactly, so a tab you opened with
`ssh user@box` is not recognised for a host configured as `ssh = "box"`; a new tab
opens instead. Herdview finds cmux in `/opt/homebrew/bin`, `/usr/local/bin` or
`cmux.app`; set `cmux_path` above the first `[[hosts]]` if it lives elsewhere.

cmux admits only processes started inside it by default, so a Herdview opened from
the Dock or Finder is refused. Run `mise run cmux:setup` once: it switches cmux's
socket to password mode with a random password in `~/.config/cmux/cmux.json`
(backing the file up first) and reloads cmux. Or set Settings › Automation to
Password by hand.

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

Beside the traffic lights in the window's title bar, a Quota strip shows how
much of each plan is used. Collapsed — the default — it holds one item per
Provider, minus anything in `hidden_providers`: the Provider's icon, its
shortest Window, and its `week`, each as a mini bar, with its percent when
there is room. A Provider with no numbers — still loading, not signed in, or
a problem with no last report — shows just its icon. A hidden Provider is not
fetched either, so its credential file is not even read.
Clicking the strip expands it in place, pushing the filter and list down. Every
Window — `5h`, `week`, `month`, or a per-model week like `week · Fable` — shows
the percent used and how long until it resets. A yellow tick on the bar marks
how much of the Window's time has passed: the bar is green while it stays behind
the tick and turns orange once it runs past it, being spent faster than the
clock, or reaches 90%. A `month`, whose length varies, has no tick and a grey
bar until 90%. A stale note appears when a Provider's numbers are old. Clicking
the header row again, or its chevron-up, collapses the strip, and it stays in
whichever state you left it next launch. The ↻ refresh button sits in the
expanded header, refreshing without collapsing, and is only visible while
expanded. The numbers come from the credentials these tools keep on this Mac,
never from the remote hosts, since every host spends the same accounts:

| Provider | Credential read |
|---|---|
| Claude | Keychain item `Claude Code-credentials` |
| Codex | `~/.codex/auth.json` |
| OpenCode Go | `opencode-go` key in `~/.local/share/opencode/auth.json`, and in pi's `~/.pi/agent/auth.json` |
| Grok | `~/.grok/auth.json`, and `xai` in pi's `~/.pi/agent/auth.json` |

They are only read. Herdview never refreshes a token and never runs a CLI (see
[ADR 0005](docs/adr/0005-quota-from-provider-apis-without-refresh.md)).
Quota belongs to an account, not to a tool: when two tools hold the same
account it is one row, and when they hold different accounts of one Provider
each gets its own row, named by the tools that hold it — `OpenCode Go · pi`
([ADR 0006](docs/adr/0006-quota-per-account-from-every-source.md)).
An account no tool has used for a few hours shows its last numbers dimmed with
"quiet · updated 3h ago": its Quota has not moved, and the next tool to run
brings fresh numbers. A Provider no tool is signed in to shows "not signed in". Quota
is fetched every 5 minutes, and when the window is shown, but only while the
window is visible; the ↻ button in the expanded strip's header fetches it at
once, unless an account is waiting out a rate limit. The first read of
Claude's Keychain item may ask for permission; choose Always Allow. None of
these usage endpoints is documented, so a row that says "unreadable response"
means a Provider changed its API.

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
mise run dev                   # debug build → build/Herdview.app, quit any running Herdview, open the new one
mise run build                 # release build/Herdview.app (CONFIG=debug for unoptimised); doesn't launch it
mise run build --reveal        # the same, then show the app in Finder
mise run app:install           # release build → /Applications/Herdview.app (INSTALL_DIR=… elsewhere), quit the old one, open it
mise run test                  # unit tests
mise run ui:shots              # window from fixtures → build/ui-shots/*.png, checks clicks and alignment
mise run ci                    # the gate before a PR: test, then ui:shots
mise run clean
mise run icon --color 5C43DC   # redraw scripts/AppIcon.icns (the default accent if --color is left out)
```

To keep a build you use every day, `mise run app:install`: it replaces
`/Applications/Herdview.app` with a fresh release build and opens it. It and
`mise run dev` both quit whichever Herdview is running first: the bundle id is the same for every build, so
opening a new one while another runs only brings the old one forward.

Or without mise: `swift test && ./scripts/build-app.sh && open build/Herdview.app`.

Logs go to the unified log: `log stream --predicate 'process == "herdview"'`.
