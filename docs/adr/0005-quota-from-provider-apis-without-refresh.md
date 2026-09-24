# 0005: Read Quota from Provider APIs with the CLIs' own credentials, never refreshing them, accepting stale numbers for an unused CLI

> Status: Accepted · Date: 2026-09-17

## Context

Herdview shows how much of each Provider's Quota is used. None of the four Providers
(Claude, Codex, OpenCode Go, Grok) has a documented usage API, but each CLI stores a
credential on this Mac that an undocumented usage endpoint accepts.

Those credentials expire: Claude's access token after about 8 hours, Grok's after 6,
Codex's after 10 days. The CLIs refresh them when they run, and Claude and Grok rotate
the refresh token as they do.

[stablyai/orca](https://github.com/stablyai/orca) handles expiry by driving the CLIs —
`codex app-server` over JSON-RPC, and `claude` in a hidden PTY with `/usage` typed into
it and the screen parsed — and refreshes the tokens of accounts it manages itself.

Source: [design spec](../superpowers/specs/2026-09-17-quota-design.md)

## Decision

Herdview reads each CLI's stored credential read-only and calls the Provider's usage
endpoint with it. It never refreshes, writes or rotates a token and never launches a
CLI. An expired credential shows the last numbers dimmed and "sign-in expired — run
`<cli>`".

This wins because an expired token means that CLI has not run for hours, so its Quota is
not moving and the last numbers are still right. Refreshing from Herdview would race the
CLI over a rotating refresh token and could sign the user out. Driving the CLIs would
spawn processes on every poll and parse screens that change with each release.

This does not amend [0001](0001-herdr-as-sole-state-source.md). That ADR is about an
Agent's Status, which still comes only from Herdr. Quota belongs to a Provider, not to
an Agent, and Herdr has no view of it.

## Consequences

A Provider whose CLI has not run for a while shows "sign-in expired" until the CLI runs
again, even though the account is fine.

Every endpoint is undocumented and can change without notice. The parsers skip what
they cannot read, and a response with nothing readable shows "unreadable response"
rather than wrong numbers.

## Alternatives considered

| Alternative | Why not chosen |
|-------------|----------------|
| Refresh tokens from Herdview and write them back | Claude and Grok rotate refresh tokens; a refresh racing the CLI's own can invalidate the one the CLI holds and sign the user out. |
| Drive the CLIs (`codex app-server`, `claude` PTY `/usage`) | A process per poll, screen parsing tied to CLI releases, and nothing equivalent for Grok or OpenCode. Orca itself disables the Claude PTY for the user's own login. |
| HTTP, with `codex app-server` as the Codex fallback | Codex tokens last 10 days; a second mechanism for one Provider buys almost nothing. |
| OpenCode Go through a pasted dashboard cookie, as orca does | OpenCode has a usage endpoint that takes the Go key the CLI already stores, so no secret needs entering or storing. |

## Updates

### 2026-09-24: Expired reads as "quiet", and a second Source can cover it

The decision stands. An expired credential is now shown as `quiet · updated <age>` with
no "run `<cli>`": nothing needs doing, as the Consequences above already argue. And
[0006](0006-quota-per-account-from-every-source.md) reads pi as a second Source, so an
Account one tool has stopped using still shows fresh numbers while another tool uses
it — still without refreshing anything.
