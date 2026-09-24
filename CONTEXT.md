# Herdview

A macOS app that mirrors the live state of coding agents running inside Herdr, on the
local machine and on remote machines, in one window listing them all, with a menu bar item
that calls the window up.

## Language

**Host**:
A machine that runs Herdr: the local Mac, or a remote machine reached over SSH.
_Avoid_: Server, box, source

**Session**:
One Herdr server on a Host, with its own socket. A Host has a default Session and any
number of named Sessions; only a running Session is watched.
_Avoid_: Workspace, instance

**Agent**:
The coding agent process Herdr has detected in one pane of a Session. Identified by Host,
Session, and pane id; it disappears when Herdr stops listing it.
_Avoid_: Pane, terminal, process

**Status**:
Herdr's classification of an Agent, taken verbatim: `idle`, `working`, `blocked`, `done`,
or `unknown`. Herdview never derives Status itself.
_Avoid_: State, waiting, registered

**Filter**:
What the window lists right now: agents matching the search text and the status scope.
It never changes Status, Notifications or the menu bar item, and it never hides an Agent
that asks for a person without saying so.
_Avoid_: search, view, query

**Transition**:
An Agent changing from one Status to another as observed by Herdview. Only transitions
into `blocked` and `done` ask for a person, and those are the ones that produce a
Highlight and a Notification. Where the Agent came from never matters.

**Highlight**:
The wash an Agent's row blinks in for as long as it is `blocked` or `done`. It keeps
asking until a person comes; the row itself never goes away to announce a change.
_Avoid_: Flash, pulse

**Notification**:
The macOS banner Herdview posts on a Transition into `blocked` or `done` — one per Agent,
replacing that Agent's previous one. It carries the same news as a Highlight to a person
who is not looking at the window. macOS owns whether it is shown; Herdview has no setting
for it.
_Avoid_: Toast, alert, popup

**Since**:
The moment Herdview observed an Agent's current Status. Herdr does not report timestamps,
so timers count from observation, not from the real change.

**Provider**:
A service that sells a plan with Quota: Claude, Codex, OpenCode Go, or Grok. A Provider
belongs to no Host; Agents on every Host spend its Accounts' Quota.
_Avoid_: Vendor, service

**Account**:
One sign-in to a Provider, the thing a Quota belongs to. Several Sources can hold the
same Account; a Provider can have several Accounts on this Mac at once.
_Avoid_: User, login, profile

**Source**:
A tool on this Mac that keeps a credential Herdview reads: `claude`, `codex`,
`opencode`, `grok`, or `pi`. A Source is not an Agent and belongs to no Host.
_Avoid_: CLI, auth file

**Quota**:
How much of an Account's plan has been used, as reported by the Provider. Made of one or
more Windows. Herdview only reads it and never estimates it.
_Avoid_: Usage, rate limit, credits

**Window**:
One limit within a Quota over a period — `5h`, `week`, `month`, or a period scoped to
one model such as `week · Fable` — holding the percent used and its Reset. Always
percent used, never percent remaining.
_Avoid_: Bucket, limit, period

**Reset**:
The moment a Window's usage returns to zero, as the Provider reports it.
