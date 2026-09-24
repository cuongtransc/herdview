# 0006: Show Quota per Account read from every Source, accepting one row per distinct Account

> Status: Accepted · Date: 2026-09-24

## Context

[0005](0005-quota-from-provider-apis-without-refresh.md) read one credential per
Provider, from the Provider's own CLI. Other tools keep their own credentials for the
same Providers: pi stores an OpenCode Go key and a Grok OAuth token in
`~/.pi/agent/auth.json`. When pi was signed in to a new OpenCode Go Account, Herdview
kept showing the old Account from `opencode`'s file — at 100% — because it never looked
anywhere else.

Source: [design spec](../superpowers/specs/2026-09-24-quota-accounts-design.md)

## Decision

Herdview reads every known Source for a Provider, groups the credentials into Accounts
by the identity the credential carries (account id, else JWT `sub`, else a hash of the
key), fetches once per Account, and shows one row per Account. Within one Account it
uses the credential with the latest expiry.

This wins because Quota belongs to an Account, not to a CLI: any single-Source rule
shows the wrong Account whenever the user switches tools, and does so silently.

It does not amend 0005. Nothing is refreshed or written; a second Source is only a
second read-only file.

## Consequences

A Provider can show two rows with the same name, distinguished only by their Sources.

Two Sources holding different grants for the same person are merged only when the
identity matches. For OpenCode Go the key is the only identity, so two keys on one
subscription would show as two rows with the same numbers.

## Alternatives considered

| Alternative | Why not chosen |
|-------------|----------------|
| Read only pi | Hides the Account whenever `opencode` or `grok` is run directly. |
| Use the most recently modified file | Right or wrong depending on which tool last wrote, with nothing on screen saying which. |
| A config key choosing the Source per Provider | Has to be changed every time the user switches tools; the same silent wrong-Account failure when it is not. |
