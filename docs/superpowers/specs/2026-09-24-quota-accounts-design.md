# Quota per Account, read from every Source

Date: 2026-09-24
Status: approved

## Purpose

Show the Quota of the Account each tool on this Mac actually spends, not only the one
the Provider's own CLI is signed in to.

The first Quota design read one credential per Provider, at the CLI's default location.
That broke as soon as a second tool held its own credential for the same Provider: pi
signed in to a new OpenCode Go Account while `opencode`'s `auth.json` still held the
old one, and Herdview kept showing the old Account's full `week` Window.

Builds on [the first Quota design](2026-09-17-quota-design.md); everything not named
here is unchanged. [ADR 0005](../../adr/0005-quota-from-provider-apis-without-refresh.md)
stands: nothing is refreshed, written or launched.

## Scope

In:

- A second Source, pi (`~/.pi/agent/auth.json`), for OpenCode Go and Grok.
- Grouping credentials into Accounts, one request and one row per Account.
- An expired credential shown as `quiet`, with no call to action (see Quiet).

Out:

- pi as a Source for Claude or Codex. pi's `auth.json` on this Mac holds neither today;
  adding one later is a new entry in the Source table, not a redesign.
- Configurable Source paths or a per-Source switch. `hidden_providers` stays per
  Provider.
- Refreshing any token (ADR 0005).

## Sources

| Provider | Source | Location | Credential |
|---|---|---|---|
| Claude | `claude` | Keychain `Claude Code-credentials` | unchanged |
| Codex | `codex` | `~/.codex/auth.json` | unchanged |
| OpenCode Go | `opencode` | `~/.local/share/opencode/auth.json` | `opencode-go.key` (unchanged) |
| OpenCode Go | `pi` | `~/.pi/agent/auth.json` | `opencode-go.key`, `type == "api_key"` |
| Grok | `grok` | `~/.grok/auth.json` | unchanged |
| Grok | `pi` | `~/.pi/agent/auth.json` | `xai.access`, `type == "oauth"`; `xai.expires` is epoch milliseconds |

pi's Grok token is a JWT from the same issuer and client as the Grok CLI's
(`iss https://auth.x.ai`, same `aud`). Its `sub` equals the Grok CLI's `user_id`, and it
is sent as `x-userid`. Checked on 2026-09-24: `GET /v1/billing?format=credits` answered
200 with pi's token.

A Source that is missing, unreadable, or lacks the Provider's entry contributes nothing.
It is not an error: most Macs have no pi.

## Account identity

An Account is identified, in order of preference, by:

1. the account id the credential carries (Codex `account_id`, Grok `user_id`);
2. the `sub` claim, when the token is a JWT (pi's `xai.access`);
3. SHA-256 of the token (OpenCode Go keys, Claude).

The id never leaves the process and is never logged or shown; only the Source names are.

Two credentials with the same Provider and id are the same Account. On this Mac today:
Grok via `grok` and via `pi` are one Account (same `sub`); OpenCode Go via `opencode`
and via `pi` are two (different keys).

A Claude access token rotates when the CLI refreshes it, so the Claude Account's id
changes then. Harmless: a rotation means a fresh token, the next fetch succeeds, and no
stale "last report" is needed across it.

## Choosing a credential

When one Account is held by several Sources, the credential with the latest expiry is
used; one without a known expiry ranks below any with one, and ties go to Source order
in the table above. That is why a Grok Account shows fresh numbers while pi runs even if
the Grok CLI has not run for a day — no refresh involved, just the other Source's token.

## Quiet

An expired credential (HTTP 401, or 403 other than OpenCode's `EntitlementError`) is
shown as `quiet`, not "sign-in expired — run `<cli>`":

- with a last report: its Windows dimmed, then `quiet · updated 3h ago`;
- without one: `quiet`.

The old wording asked the user to act, and there is nothing to do. A token expires
because no Source has used the Account for hours, so its Quota has not moved and the
dimmed numbers are still right; the next time any Source runs, it refreshes its own
token and the next poll picks it up. The one case where the numbers are really stale —
the Account used somewhere Herdview cannot read, such as grok.com — is not one that
running a CLI to refresh a gauge would be worth it for.

`QuotaProblem.signInExpired` becomes `.quiet`; `QuotaProvider.signInCommand` goes, as
nothing shows it any more. The log line keeps saying "sign-in expired": the log is for
diagnosing, the row is for glancing.

## Model

- `QuotaSource`: `claude`, `codex`, `opencode`, `grok`, `pi`; its raw value is the only
  thing about a credential Herdview shows.
- `QuotaCredential(token:accountId:)` is unchanged: a credential carries no Source of its
  own, so the Source travels beside it as a `(source:credential:)` pair.
- `QuotaAccountKey { provider, id }` — `Hashable` on `provider + id`.
- `QuotaAccount { key, sources: [QuotaSource] }`, `provider` read through `key`.
- `QuotaAccounts.group([(source: QuotaSource, credential: QuotaCredential)], provider:) ->
  [(account: QuotaAccount, credential: QuotaCredential)]` — pure, in `HerdviewCore`,
  applies the identity and choice rules above. Accounts come out in Source order of their
  first Source, so rows do not jump between polls.

## Flow

Each poll, per visible Provider:

1. Read every Source of the Provider (`CredentialReader`).
2. `QuotaAccounts.group` them.
3. No credential from any Source → the Provider's single `notSignedIn` row, as today.
4. Otherwise one fetch per Account; each result updates that Account's entry.
   Accounts no longer found are dropped from the store.

Scheduling and cancellation stay per Provider: one fetch reads every Source, then asks
for each Account in turn. Rate-limit waits move to per-Account keys, so a rate limit on
one Account does not hold back another; a Provider is skipped only while every one of
its Accounts is waiting.

Expiry comes from the token itself (JWT `exp`), for every Source alike; pi's
`xai.expires` is not read.

## UI

- A Provider with one Account renders exactly as today.
- A Provider with several Accounts renders one row and one title-bar gauge per Account,
  titled `<Provider> · <sources joined by ", ">`, e.g. `OpenCode Go · pi`,
  `OpenCode Go · opencode`.
- Order: Provider order as today, then Account order from `group`.

## Testing

TDD in `HerdviewCoreTests`:

- pi `auth.json` parsing: `opencode-go` api key; `xai` oauth whose `access` is a JWT;
  missing entries; wrong `type`; malformed JSON.
- Identity: account id beats `sub` beats hash; a non-JWT token falls to the hash.
- Grouping: same `sub` from two Sources → one Account with both Sources; two different
  keys → two Accounts; latest expiry wins; no expiry loses; tie → Source order.
- Entry carry-over: an Account's `last` report survives a failed fetch; a vanished
  Account's entry is dropped.
- Row title: one Account → Provider name; several → name with Sources.
- Quiet: message is `quiet`; with a last report the note is `quiet · updated <age>`.

`mise run ci` green; `ui:shots` fixture with two OpenCode Go Accounts checked by eye.
