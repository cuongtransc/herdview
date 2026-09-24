# Quota per Account Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read Quota credentials from every Source (adding pi), group them into Accounts, fetch and show one row per Account, and show an expired credential as `quiet`.

**Architecture:** All decisions live in `HerdviewCore` as pure, unit-tested code: `QuotaSource` (where a credential lives), `JWTClaims` (subject/expiry of a token), `QuotaAccounts.group` (identity and choice), `QuotaBoard` (the panel's state and its rows). The App layer (`CredentialReader`, `QuotaStore`, `QuotaMonitor`, the two views, `UIShots`) only wires these together.

**Tech Stack:** Swift 5.10, SwiftPM, SwiftUI/AppKit, XCTest, CryptoKit, macOS 13+. Tasks run through mise.

**Spec:** `docs/superpowers/specs/2026-09-24-quota-accounts-design.md`

## Global Constraints

- Work in the worktree `/Users/connor/Dev/PCT/01-AI/21-AI-Coding-Agent/herdview/.worktrees/feat-quota-accounts`, branch `feat/quota-accounts`. Never commit to `main`.
- Nothing refreshes, writes or rotates a token, and nothing launches a CLI (ADR 0005).
- A token, key, account id, `sub` or Account id is never logged, shown or put in a row title. Only Source names (`claude`, `codex`, `opencode`, `grok`, `pi`) may appear.
- Source order is the table order: Claude `[claude]`, Codex `[codex]`, OpenCode Go `[opencode, pi]`, Grok `[grok, pi]`.
- pi file: `~/.pi/agent/auth.json`. OpenCode Go entry `opencode-go` with `type == "api_key"` → `key`. Grok entry `xai` with `type == "oauth"` → `access`, `x-userid` = the token's `sub`.
- Account identity: the credential's `accountId`, else the JWT `sub`, else SHA-256 hex of the token.
- The chosen credential for an Account is the one whose JWT `exp` is latest; no readable `exp` ranks below any; ties keep the earlier Source.
- Row title: `<Provider displayName>` when the Provider has one Account, `<displayName> · <sources joined by ", ">` when it has several.
- An expired credential (`QuotaOutcome.signInExpired`) shows `quiet`, or `quiet · updated <age>` under dimmed last numbers. The log keeps saying "sign-in expired".
- Match the surrounding style: doc comments that say why, no force unwraps in production code.
- Unit tests: `swift test`. Full gate: `mise run ci` (tests, then `ui:shots`). Log long runs to a file: `mise run ci > /tmp/herdview-ci-$(date +%s).log 2>&1; echo "exit=$?"`.

## Review Focus

- A pi `auth.json` that exists but has no `opencode-go` / `xai` entry, a wrong `type`, or is not JSON: that Source contributes nothing and the other Source's Account still shows. Covered by Task 1 tests.
- A Keychain read that fails after Claude had an Account: the last numbers stay on screen, dimmed, with the failure reason, instead of the row turning into "not signed in". Covered in Task 5's `fetch` code; checked by reading, since the monitor has no unit tests.
- One Account rate-limited while another of the same Provider is not: the other still fetches. Covered by Task 5's `waitUntil` code.
- An Account that disappears (user signs pi out): its row and entry go at the next poll, and an entry for it set late by an in-flight fetch is ignored. Covered by Task 4 tests.
- A token that looks like a JWT but has a malformed payload: identity falls back to the hash, expiry to "none". Covered by Task 1 and Task 2 tests.

---

### Task 1: Sources, JWT claims and pi parsing

**Files:**
- Create: `Sources/HerdviewCore/QuotaSource.swift`
- Create: `Sources/HerdviewCore/JWTClaims.swift`
- Modify: `Sources/HerdviewCore/QuotaCredentials.swift` (replace `filePath(for provider:)`, add `parse(_:from:_:)`)
- Create: `Tests/HerdviewCoreTests/JWTFixture.swift`
- Create: `Tests/HerdviewCoreTests/JWTClaimsTests.swift`
- Modify: `Tests/HerdviewCoreTests/QuotaCredentialsTests.swift`

**Interfaces:**
- Consumes: `QuotaProvider`, `QuotaCredential(token:accountId:)`, `QuotaCredentials.parse(_ provider:_ data:)` (existing).
- Produces:
  - `public enum QuotaSource: String, CaseIterable, Sendable { case claude, codex, opencode, grok, pi }` with `public static func sources(for provider: QuotaProvider) -> [QuotaSource]`
  - `enum JWTClaims { static func subject(of token: String) -> String?; static func expiry(of token: String) -> Date? }` (internal)
  - `QuotaCredentials.filePath(for source: QuotaSource, home: String) -> String?` (replaces the provider overload)
  - `QuotaCredentials.parse(_ provider: QuotaProvider, from source: QuotaSource, _ data: Data) -> QuotaCredential?`
  - Test helper `func jwt(_ claims: [String: Any]) -> String`

- [ ] **Step 1: Write the test helper and failing tests**

`Tests/HerdviewCoreTests/JWTFixture.swift`:

```swift
import Foundation

/// An unsigned JWT carrying `claims`, shaped like the access tokens Grok and
/// Codex store. Nothing in Herdview verifies a signature, so none is needed.
func jwt(_ claims: [String: Any]) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: claims)) ?? Data()
    let payload = data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "eyJhbGciOiJub25lIn0.\(payload).sig"
}
```

`Tests/HerdviewCoreTests/JWTClaimsTests.swift`:

```swift
import XCTest
@testable import HerdviewCore

final class JWTClaimsTests: XCTestCase {
    func testReadsSubjectAndExpiry() {
        let token = jwt(["sub": "user-1", "exp": 1_790_261_909])
        XCTAssertEqual(JWTClaims.subject(of: token), "user-1")
        XCTAssertEqual(JWTClaims.expiry(of: token), Date(timeIntervalSince1970: 1_790_261_909))
    }

    /// Base64url payloads drop their padding; every length must still decode.
    func testDecodesPayloadsOfEveryPaddingLength() {
        for sub in ["a", "ab", "abc", "abcd"] {
            XCTAssertEqual(JWTClaims.subject(of: jwt(["sub": sub])), sub)
        }
    }

    func testAnythingElseHasNoClaims() {
        for token in ["", "sk-opencode-go-key", "a.b", "a.!!!.c", "a.b.c.d", jwt(["sub": ""]), jwt(["exp": "soon"])] {
            XCTAssertNil(JWTClaims.subject(of: token), token)
            XCTAssertNil(JWTClaims.expiry(of: token), token)
        }
    }
}
```

Append to `QuotaCredentialsTests` (inside the class), and replace the existing `testFilePaths`:

```swift
    func testFilePaths() {
        XCTAssertNil(QuotaCredentials.filePath(for: .claude, home: "/Users/me"))
        XCTAssertEqual(QuotaCredentials.filePath(for: .codex, home: "/Users/me"), "/Users/me/.codex/auth.json")
        XCTAssertEqual(QuotaCredentials.filePath(for: .opencode, home: "/Users/me"), "/Users/me/.local/share/opencode/auth.json")
        XCTAssertEqual(QuotaCredentials.filePath(for: .grok, home: "/Users/me"), "/Users/me/.grok/auth.json")
        XCTAssertEqual(QuotaCredentials.filePath(for: .pi, home: "/Users/me"), "/Users/me/.pi/agent/auth.json")
    }

    func testSourcesPerProviderOwnCLIFirst() {
        XCTAssertEqual(QuotaSource.sources(for: .claude), [.claude])
        XCTAssertEqual(QuotaSource.sources(for: .codex), [.codex])
        XCTAssertEqual(QuotaSource.sources(for: .opencodeGo), [.opencode, .pi])
        XCTAssertEqual(QuotaSource.sources(for: .grok), [.grok, .pi])
    }

    /// Every Source but pi holds only its own Provider, in the format it always had.
    func testNonPiSourcesReadAsBefore() {
        let json = Data(#"{"opencode-go":{"type":"api","key":"go-key"}}"#.utf8)
        XCTAssertEqual(QuotaCredentials.parse(.opencodeGo, from: .opencode, json), QuotaCredential(token: "go-key"))
    }

    func testPiOpenCodeGoKey() {
        let json = Data(#"{"opencode-go":{"type":"api_key","key":"pi-go"},"xai":{"type":"oauth","access":"x"}}"#.utf8)
        XCTAssertEqual(QuotaCredentials.parse(.opencodeGo, from: .pi, json), QuotaCredential(token: "pi-go"))
    }

    /// pi keeps no user id; the token's subject is what Grok's CLI stores as `user_id`.
    func testPiGrokTokenCarriesItsSubjectAsTheUserId() {
        let token = jwt(["sub": "u1", "exp": 1_790_261_909])
        let json = Data(#"{"xai":{"type":"oauth","access":"\#(token)","refresh":"r","expires":1790261909000}}"#.utf8)
        XCTAssertEqual(QuotaCredentials.parse(.grok, from: .pi, json), QuotaCredential(token: token, accountId: "u1"))
    }

    func testPiWithoutTheEntryOrWithTheWrongTypeHasNothing() {
        let other = Data(#"{"anthropic":{"type":"oauth","access":"a"}}"#.utf8)
        XCTAssertNil(QuotaCredentials.parse(.opencodeGo, from: .pi, other))
        XCTAssertNil(QuotaCredentials.parse(.grok, from: .pi, other))
        let wrongType = Data(#"{"opencode-go":{"type":"oauth","key":"k"},"xai":{"type":"api_key","access":"a"}}"#.utf8)
        XCTAssertNil(QuotaCredentials.parse(.opencodeGo, from: .pi, wrongType))
        XCTAssertNil(QuotaCredentials.parse(.grok, from: .pi, wrongType))
        XCTAssertNil(QuotaCredentials.parse(.opencodeGo, from: .pi, Data("not json".utf8)))
        XCTAssertNil(QuotaCredentials.parse(.grok, from: .pi, Data(#"{"xai":{"type":"oauth","access":""}}"#.utf8)))
    }

    /// pi is not a Source for Claude or Codex, whatever its file holds.
    func testPiHoldsNoClaudeOrCodex() {
        let json = Data(#"{"claudeAiOauth":{"accessToken":"t"},"tokens":{"access_token":"t"}}"#.utf8)
        XCTAssertNil(QuotaCredentials.parse(.claude, from: .pi, json))
        XCTAssertNil(QuotaCredentials.parse(.codex, from: .pi, json))
    }
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --filter 'JWTClaimsTests|QuotaCredentialsTests' 2>&1 | tail -20`
Expected: build failure — `cannot find 'JWTClaims' in scope`, `cannot find 'QuotaSource' in scope`.

- [ ] **Step 3: Implement**

`Sources/HerdviewCore/QuotaSource.swift`:

```swift
import Foundation

/// A tool on this Mac that keeps a credential Herdview reads. A Source is not
/// an Agent and belongs to no Host; its raw value is the only thing about a
/// credential Herdview ever shows.
public enum QuotaSource: String, CaseIterable, Sendable {
    case claude
    case codex
    case opencode
    case grok
    case pi

    /// Every Source that can hold a credential for `provider`, the Provider's
    /// own CLI first. The order decides Account order and breaks ties.
    public static func sources(for provider: QuotaProvider) -> [QuotaSource] {
        switch provider {
        case .claude: return [.claude]
        case .codex: return [.codex]
        case .opencodeGo: return [.opencode, .pi]
        case .grok: return [.grok, .pi]
        }
    }
}
```

`Sources/HerdviewCore/JWTClaims.swift`:

```swift
import Foundation

/// The two claims Herdview reads from an access token that is a JWT. The
/// signature is not checked: the token only ever goes back to its issuer,
/// which checks it. Anything that is not a readable JWT has no claims.
enum JWTClaims {
    static func subject(of token: String) -> String? {
        guard let subject = payload(of: token)?["sub"] as? String, !subject.isEmpty else { return nil }
        return subject
    }

    static func expiry(of token: String) -> Date? {
        guard let seconds = payload(of: token)?["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: seconds.doubleValue)
    }

    private static func payload(of token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
```

In `Sources/HerdviewCore/QuotaCredentials.swift`, replace the whole `filePath(for provider:home:)` function (and its doc comment) with:

```swift
    /// Where `source` keeps its credentials, or `nil` for Claude, whose
    /// credential is in the Keychain.
    public static func filePath(for source: QuotaSource, home: String) -> String? {
        switch source {
        case .claude: return nil
        case .codex: return home + "/.codex/auth.json"
        case .opencode: return home + "/.local/share/opencode/auth.json"
        case .grok: return home + "/.grok/auth.json"
        case .pi: return home + "/.pi/agent/auth.json"
        }
    }
```

and add, directly after the existing `parse(_ provider:_ data:)` function:

```swift
    /// The credential `source` holds for `provider`. Every Source but pi is a
    /// Provider's own CLI and keeps the format `parse(_:_:)` reads; pi keeps
    /// several Providers in one file, each under its own key and type.
    public static func parse(_ provider: QuotaProvider, from source: QuotaSource, _ data: Data) -> QuotaCredential? {
        guard source == .pi else { return parse(provider, data) }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        switch provider {
        case .opencodeGo:
            guard let entry = json["opencode-go"] as? [String: Any],
                  entry["type"] as? String == "api_key" else { return nil }
            return credential(token: entry["key"], accountId: nil)
        case .grok:
            // pi keeps no user id. The token's subject is the id Grok's CLI
            // stores, and the billing endpoint wants it as `x-userid`.
            guard let entry = json["xai"] as? [String: Any],
                  entry["type"] as? String == "oauth",
                  let token = entry["access"] as? String else { return nil }
            return credential(token: token, accountId: JWTClaims.subject(of: token))
        case .claude, .codex:
            return nil
        }
    }
```

`Sources/App/CredentialReader.swift` still calls `QuotaCredentials.filePath(for: provider, …)`, which no longer exists. Keep the App building by changing line 20 of `CredentialReader.read(_:)` to use the Provider's own Source (Task 5 replaces this function):

```swift
        if let path = QuotaCredentials.filePath(for: QuotaSource.sources(for: provider)[0], home: NSHomeDirectory()) {
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test 2>&1 | tail -5`
Expected: `Executed N tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/HerdviewCore/QuotaSource.swift Sources/HerdviewCore/JWTClaims.swift Sources/HerdviewCore/QuotaCredentials.swift Sources/App/CredentialReader.swift Tests/HerdviewCoreTests/JWTFixture.swift Tests/HerdviewCoreTests/JWTClaimsTests.swift Tests/HerdviewCoreTests/QuotaCredentialsTests.swift
git commit -m "feat(quota): read pi as a second Source for OpenCode Go and Grok"
```

---

### Task 2: Group credentials into Accounts

**Files:**
- Create: `Sources/HerdviewCore/QuotaAccount.swift`
- Create: `Tests/HerdviewCoreTests/QuotaAccountsTests.swift`

**Interfaces:**
- Consumes: `QuotaSource`, `JWTClaims.subject(of:)`, `JWTClaims.expiry(of:)`, test helper `jwt(_:)` (Task 1); `QuotaCredential`.
- Produces:
  - `public struct QuotaAccountKey: Hashable, Sendable { public let provider: QuotaProvider; public let id: String; public init(provider:id:) }`
  - `public struct QuotaAccount: Equatable, Sendable { public let key: QuotaAccountKey; public let sources: [QuotaSource]; public var provider: QuotaProvider; public init(key:sources:) }`
  - `public enum QuotaAccounts { public static func identity(of: QuotaCredential) -> String; public static func group(_ found: [(source: QuotaSource, credential: QuotaCredential)], provider: QuotaProvider) -> [(account: QuotaAccount, credential: QuotaCredential)] }`

- [ ] **Step 1: Write the failing tests**

`Tests/HerdviewCoreTests/QuotaAccountsTests.swift`:

```swift
import XCTest
@testable import HerdviewCore

final class QuotaAccountsTests: XCTestCase {
    func testIdentityPrefersTheAccountIdThenTheSubjectThenAHash() {
        let token = jwt(["sub": "sub-1"])
        XCTAssertEqual(QuotaAccounts.identity(of: QuotaCredential(token: token, accountId: "acct")), "acct")
        XCTAssertEqual(QuotaAccounts.identity(of: QuotaCredential(token: token)), "sub-1")
        // SHA-256 of "key": the id never carries the key itself.
        XCTAssertEqual(QuotaAccounts.identity(of: QuotaCredential(token: "key")),
                       "2c70e12b7a0646f92279f427c7b38e7334d8e5389cff167a1dc30e73f826b683")
    }

    /// Grok's CLI and pi hold two grants for one person: same subject, one Account.
    func testSameIdentityFromTwoSourcesIsOneAccount() {
        let grok = QuotaCredential(token: jwt(["sub": "u1", "exp": 100]), accountId: "u1")
        let pi = QuotaCredential(token: jwt(["sub": "u1", "exp": 200]), accountId: "u1")
        let grouped = QuotaAccounts.group([(source: .grok, credential: grok), (source: .pi, credential: pi)], provider: .grok)
        XCTAssertEqual(grouped.map(\.account),
                       [QuotaAccount(key: QuotaAccountKey(provider: .grok, id: "u1"), sources: [.grok, .pi])])
        XCTAssertEqual(grouped.map(\.credential), [pi])
    }

    func testDifferentKeysAreTwoAccountsInSourceOrder() {
        let old = QuotaCredential(token: "old-key")
        let new = QuotaCredential(token: "new-key")
        let grouped = QuotaAccounts.group([(source: .opencode, credential: old), (source: .pi, credential: new)],
                                          provider: .opencodeGo)
        XCTAssertEqual(grouped.map(\.account.sources), [[.opencode], [.pi]])
        XCTAssertEqual(grouped.map(\.credential), [old, new])
        XCTAssertEqual(grouped.map(\.account.provider), [.opencodeGo, .opencodeGo])
    }

    func testTheLatestExpiryWinsAndNoExpiryLoses() {
        let later = QuotaCredential(token: jwt(["sub": "u", "exp": 300]), accountId: "u")
        let earlier = QuotaCredential(token: jwt(["sub": "u", "exp": 100]), accountId: "u")
        let none = QuotaCredential(token: "opaque", accountId: "u")
        XCTAssertEqual(QuotaAccounts.group([(source: .grok, credential: later), (source: .pi, credential: earlier)],
                                           provider: .grok).map(\.credential), [later])
        XCTAssertEqual(QuotaAccounts.group([(source: .grok, credential: none), (source: .pi, credential: earlier)],
                                           provider: .grok).map(\.credential), [earlier])
        XCTAssertEqual(QuotaAccounts.group([(source: .grok, credential: earlier), (source: .pi, credential: none)],
                                           provider: .grok).map(\.credential), [earlier])
    }

    func testATieKeepsTheEarlierSource() {
        let first = QuotaCredential(token: jwt(["sub": "u", "exp": 100, "n": 1]), accountId: "u")
        let second = QuotaCredential(token: jwt(["sub": "u", "exp": 100, "n": 2]), accountId: "u")
        XCTAssertEqual(QuotaAccounts.group([(source: .grok, credential: first), (source: .pi, credential: second)],
                                           provider: .grok).map(\.credential), [first])
    }

    func testNothingFoundIsNoAccount() {
        XCTAssertTrue(QuotaAccounts.group([], provider: .codex).isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --filter QuotaAccountsTests 2>&1 | tail -20`
Expected: build failure — `cannot find 'QuotaAccounts' in scope`.

- [ ] **Step 3: Implement**

`Sources/HerdviewCore/QuotaAccount.swift`:

```swift
import CryptoKit
import Foundation

/// Which Account an entry belongs to: its Provider and the identity its
/// credential carries. The id is never shown or logged.
public struct QuotaAccountKey: Hashable, Sendable {
    public let provider: QuotaProvider
    public let id: String

    public init(provider: QuotaProvider, id: String) {
        self.provider = provider
        self.id = id
    }
}

/// One sign-in to a Provider, and every Source on this Mac that holds it.
public struct QuotaAccount: Equatable, Sendable {
    public let key: QuotaAccountKey
    public let sources: [QuotaSource]

    public var provider: QuotaProvider { key.provider }

    public init(key: QuotaAccountKey, sources: [QuotaSource]) {
        self.key = key
        self.sources = sources
    }
}

/// Turns the credentials read from every Source into Accounts. Quota belongs
/// to an Account, so two Sources holding one Account ask once, and two
/// Accounts of one Provider each get a row (ADR 0006).
public enum QuotaAccounts {
    /// The account id the credential carries, else its JWT subject, else a
    /// SHA-256 of the token: an API key has no identity but itself, and the
    /// hash keeps the key out of every place the id goes.
    public static func identity(of credential: QuotaCredential) -> String {
        if let account = credential.accountId { return account }
        if let subject = JWTClaims.subject(of: credential.token) { return subject }
        return SHA256.hash(data: Data(credential.token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// `found` in Source order. Accounts come out in the order their first
    /// Source was read, so rows keep their places between polls. Within an
    /// Account the credential that expires last is used: a tool still running
    /// keeps the numbers fresh after another has gone quiet.
    public static func group(_ found: [(source: QuotaSource, credential: QuotaCredential)],
                             provider: QuotaProvider) -> [(account: QuotaAccount, credential: QuotaCredential)] {
        var order: [String] = []
        var sources: [String: [QuotaSource]] = [:]
        var chosen: [String: QuotaCredential] = [:]
        for (source, credential) in found {
            let id = identity(of: credential)
            guard let current = chosen[id] else {
                order.append(id)
                sources[id] = [source]
                chosen[id] = credential
                continue
            }
            if !sources[id, default: []].contains(source) { sources[id, default: []].append(source) }
            if outlasts(credential, current) { chosen[id] = credential }
        }
        return order.compactMap { id in
            guard let credential = chosen[id] else { return nil }
            let account = QuotaAccount(key: QuotaAccountKey(provider: provider, id: id), sources: sources[id, default: []])
            return (account: account, credential: credential)
        }
    }

    /// Whether `candidate` expires strictly after `current`. A token with no
    /// readable expiry never beats one with, and a tie keeps the earlier Source.
    static func outlasts(_ candidate: QuotaCredential, _ current: QuotaCredential) -> Bool {
        guard let new = JWTClaims.expiry(of: candidate.token) else { return false }
        guard let old = JWTClaims.expiry(of: current.token) else { return true }
        return new > old
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test 2>&1 | tail -5`
Expected: `Executed N tests, with 0 failures`. If the SHA-256 literal fails, verify with `printf key | shasum -a 256` and fix the literal, not the code.

- [ ] **Step 5: Commit**

```bash
git add Sources/HerdviewCore/QuotaAccount.swift Tests/HerdviewCoreTests/QuotaAccountsTests.swift
git commit -m "feat(quota): group credentials into Accounts by identity"
```

---

### Task 3: Show an expired credential as quiet

**Files:**
- Modify: `Sources/HerdviewCore/QuotaEntry.swift:4-17` (`QuotaProblem`), `:47-48` (`applying`)
- Modify: `Sources/HerdviewCore/Quota.swift:38-47` (remove `signInCommand`)
- Modify: `Sources/HerdviewCore/UIShotFixtures.swift:48` (`.signInExpired` → `.quiet`)
- Modify: `Sources/App/QuotaRows.swift:71,73`, `Sources/App/QuotaTitleBar.swift:260` (`message(for: provider)` → `message`)
- Modify: `Tests/HerdviewCoreTests/QuotaEntryTests.swift:22-44`

**Interfaces:**
- Consumes: nothing new.
- Produces: `QuotaProblem.quiet` (replaces `.signInExpired`); `QuotaProblem.message: String` (replaces `message(for:)`). `QuotaOutcome.signInExpired` is unchanged.

- [ ] **Step 1: Change the tests first**

In `QuotaEntryTests.testProblemsKeepTheLastReport`, replace the three `.signInExpired` expectations so the method reads:

```swift
    /// The last numbers survive every problem that says nothing about them.
    func testProblemsKeepTheLastReport() {
        let last = QuotaReport(provider: .claude, windows: windows, fetchedAt: then)
        XCTAssertEqual(ok.applying(.signInExpired, provider: .claude, now: now), .problem(.quiet, last: last))
        XCTAssertEqual(ok.applying(.rateLimited(until: now), provider: .claude, now: now), .problem(.rateLimited, last: last))
        XCTAssertEqual(ok.applying(.failed("HTTP 500"), provider: .claude, now: now), .problem(.failed("HTTP 500"), last: last))

        let failedTwice = ok.applying(.failed("HTTP 500"), provider: .claude, now: now)
            .applying(.signInExpired, provider: .claude, now: now)
        XCTAssertEqual(failedTwice, .problem(.quiet, last: last))
    }
```

Replace `testMessages` with:

```swift
    /// An expired credential asks nothing of the user: no Source has used the
    /// Account lately, so there is nothing to do and the numbers still hold.
    func testMessages() {
        XCTAssertEqual(QuotaProblem.quiet.message, "quiet")
        XCTAssertEqual(QuotaProblem.noSubscription.message, "no Go subscription")
        XCTAssertEqual(QuotaProblem.rateLimited.message, "rate limited")
        XCTAssertEqual(QuotaProblem.failed("Keychain access denied").message, "Keychain access denied")
    }
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --filter QuotaEntryTests 2>&1 | tail -20`
Expected: build failure — `type 'QuotaProblem' has no member 'quiet'`.

- [ ] **Step 3: Implement**

In `Sources/HerdviewCore/QuotaEntry.swift`, replace the `QuotaProblem` enum with:

```swift
/// Why a Provider's row cannot show fresh numbers.
public enum QuotaProblem: Equatable, Sendable {
    /// The credential has expired because no Source has used the Account for
    /// hours. Its Quota has not moved either, and the next Source to run
    /// refreshes its own token, so there is nothing to ask of the user.
    case quiet
    case noSubscription
    case rateLimited
    case failed(String)

    public var message: String {
        switch self {
        case .quiet: return "quiet"
        case .noSubscription: return "no Go subscription"
        case .rateLimited: return "rate limited"
        case .failed(let reason): return reason
        }
    }
}
```

and in `applying(_:provider:now:)` change

```swift
        case .signInExpired:
            return .problem(.signInExpired, last: lastReport)
```

to

```swift
        case .signInExpired:
            return .problem(.quiet, last: lastReport)
```

In `Sources/HerdviewCore/Quota.swift`, delete the `signInCommand` property and its doc comment (the block starting `/// What to run to bring an expired sign-in back.`).

In `Sources/HerdviewCore/UIShotFixtures.swift` change `.grok: .problem(.signInExpired, last:` to `.grok: .problem(.quiet, last:`.

In `Sources/App/QuotaRows.swift` change `problem.message(for: provider)` to `problem.message` (two places, lines 71 and 73). In `Sources/App/QuotaTitleBar.swift` line 260 change `problem.message(for: provider)` to `problem.message`.

- [ ] **Step 4: Run the tests and the build**

Run: `swift test 2>&1 | tail -5 && swift build 2>&1 | tail -3`
Expected: `0 failures`, then `Build complete!`. `rg -n "signInCommand|message\(for" Sources Tests` prints nothing (exit 1).

- [ ] **Step 5: Commit**

```bash
git add Sources/HerdviewCore/QuotaEntry.swift Sources/HerdviewCore/Quota.swift Sources/HerdviewCore/UIShotFixtures.swift Sources/App/QuotaRows.swift Sources/App/QuotaTitleBar.swift Tests/HerdviewCoreTests/QuotaEntryTests.swift
git commit -m "feat(quota): show an expired credential as quiet, not sign-in expired"
```

---

### Task 4: The Quota board and its rows

**Files:**
- Create: `Sources/HerdviewCore/QuotaBoard.swift`
- Create: `Tests/HerdviewCoreTests/QuotaBoardTests.swift`
- Modify: `Sources/HerdviewCore/UIShotFixtures.swift` (`quota(now:)` returns a `QuotaBoard`)

**Interfaces:**
- Consumes: `QuotaAccount`, `QuotaAccountKey` (Task 2); `QuotaEntry`, `QuotaProblem.quiet` (Task 3).
- Produces:
  - `public struct QuotaRowModel: Equatable, Identifiable, Sendable { public let id: String; public let provider: QuotaProvider; public let title: String; public let entry: QuotaEntry }`
  - `public struct QuotaBoard: Equatable, Sendable` with `init(providers: [QuotaProvider])`, `providers`, `accounts(of: QuotaProvider) -> [QuotaAccount]`, `mutating setAccounts(_: [QuotaAccount], for: QuotaProvider)`, `mutating setProviderEntry(_: QuotaEntry, for: QuotaProvider)`, `mutating set(_: QuotaEntry, for: QuotaAccountKey)`, `entry(for: QuotaAccountKey) -> QuotaEntry`, `rows: [QuotaRowModel]`
  - `UIShotFixtures.quota(now: Date) -> QuotaBoard` (was `[QuotaProvider: QuotaEntry]`)

- [ ] **Step 1: Write the failing tests**

`Tests/HerdviewCoreTests/QuotaBoardTests.swift`:

```swift
import XCTest
@testable import HerdviewCore

final class QuotaBoardTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_651_000)

    private func account(_ provider: QuotaProvider, _ id: String, _ sources: [QuotaSource]) -> QuotaAccount {
        QuotaAccount(key: QuotaAccountKey(provider: provider, id: id), sources: sources)
    }

    private func report(_ provider: QuotaProvider, _ used: Double) -> QuotaEntry {
        .ok(QuotaReport(provider: provider, windows: [QuotaWindow(label: "week", usedPercent: used, resetsAt: nil)],
                        fetchedAt: now))
    }

    func testBeforeAnyReadEveryProviderIsOneLoadingRow() {
        let board = QuotaBoard(providers: [.claude, .grok])
        XCTAssertEqual(board.rows.map(\.title), ["Claude", "Grok"])
        XCTAssertEqual(board.rows.map(\.entry), [.loading, .loading])
    }

    func testOneAccountKeepsThePlainProviderName() {
        var board = QuotaBoard(providers: [.grok])
        let grok = account(.grok, "u1", [.grok, .pi])
        board.setAccounts([grok], for: .grok)
        board.set(report(.grok, 45), for: grok.key)
        XCTAssertEqual(board.rows.map(\.title), ["Grok"])
        XCTAssertEqual(board.rows.map(\.entry), [report(.grok, 45)])
    }

    func testSeveralAccountsAreNamedByTheirSources() {
        var board = QuotaBoard(providers: [.opencodeGo, .grok])
        board.setAccounts([account(.opencodeGo, "a", [.opencode]), account(.opencodeGo, "b", [.pi])], for: .opencodeGo)
        board.setProviderEntry(.notSignedIn, for: .grok)
        XCTAssertEqual(board.rows.map(\.title), ["OpenCode Go · opencode", "OpenCode Go · pi", "Grok"])
        XCTAssertEqual(board.rows.map(\.entry), [.loading, .loading, .notSignedIn])
        XCTAssertEqual(Set(board.rows.map(\.id)).count, 3)
    }

    /// Re-reading the same Accounts must not throw away their numbers.
    func testAnAccountFoundAgainKeepsItsEntry() {
        var board = QuotaBoard(providers: [.grok])
        let grok = account(.grok, "u1", [.grok])
        board.setAccounts([grok], for: .grok)
        board.set(report(.grok, 45), for: grok.key)
        board.setAccounts([account(.grok, "u1", [.grok, .pi])], for: .grok)
        XCTAssertEqual(board.entry(for: grok.key), report(.grok, 45))
        XCTAssertEqual(board.rows.map(\.title), ["Grok"])
    }

    func testAVanishedAccountLosesItsRowAndItsEntry() {
        var board = QuotaBoard(providers: [.opencodeGo])
        let old = account(.opencodeGo, "a", [.opencode])
        let new = account(.opencodeGo, "b", [.pi])
        board.setAccounts([old, new], for: .opencodeGo)
        board.set(report(.opencodeGo, 100), for: old.key)
        board.setAccounts([new], for: .opencodeGo)
        XCTAssertEqual(board.rows.map(\.title), ["OpenCode Go"])
        XCTAssertEqual(board.entry(for: old.key), .loading)

        // A fetch still in flight for the gone Account must not bring it back.
        board.set(report(.opencodeGo, 100), for: old.key)
        XCTAssertEqual(board.entry(for: old.key), .loading)
    }

    func testNoAccountLeftShowsTheProviderEntry() {
        var board = QuotaBoard(providers: [.claude])
        let claude = account(.claude, "h", [.claude])
        board.setAccounts([claude], for: .claude)
        board.set(report(.claude, 10), for: claude.key)
        board.setProviderEntry(.notSignedIn, for: .claude)
        XCTAssertEqual(board.rows.map(\.entry), [.notSignedIn])
        XCTAssertEqual(board.accounts(of: .claude), [])
        XCTAssertEqual(board.entry(for: claude.key), .loading)
    }

    func testTheFixtureShowsTwoOpenCodeAccounts() {
        let titles = UIShotFixtures.quota(now: now).rows.map(\.title)
        XCTAssertEqual(titles, ["Claude", "Codex", "OpenCode Go · opencode", "OpenCode Go · pi", "Grok"])
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --filter QuotaBoardTests 2>&1 | tail -20`
Expected: build failure — `cannot find 'QuotaBoard' in scope`.

- [ ] **Step 3: Implement**

`Sources/HerdviewCore/QuotaBoard.swift`:

```swift
import Foundation

/// One line of the Quota panel, and one gauge of the collapsed strip.
public struct QuotaRowModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let provider: QuotaProvider
    public let title: String
    public let entry: QuotaEntry
}

/// What the Quota panel knows: for each watched Provider either its Accounts
/// with an entry each, or — when no Source holds one — a single entry for the
/// Provider (`.notSignedIn`, or a Source that could not be read).
public struct QuotaBoard: Equatable, Sendable {
    public let providers: [QuotaProvider]
    private var accountsByProvider: [QuotaProvider: [QuotaAccount]] = [:]
    private var providerEntries: [QuotaProvider: QuotaEntry] = [:]
    private var entries: [QuotaAccountKey: QuotaEntry] = [:]

    public init(providers: [QuotaProvider]) {
        self.providers = providers
    }

    public func accounts(of provider: QuotaProvider) -> [QuotaAccount] {
        accountsByProvider[provider] ?? []
    }

    /// The Accounts one read of every Source found. An Account found again
    /// keeps its entry — its sources may have changed, its numbers have not —
    /// and one no longer found goes, entry and all.
    public mutating func setAccounts(_ found: [QuotaAccount], for provider: QuotaProvider) {
        for account in accounts(of: provider) where !found.contains(where: { $0.key == account.key }) {
            entries[account.key] = nil
        }
        accountsByProvider[provider] = found
        providerEntries[provider] = nil
    }

    /// No Source holds an Account for `provider`.
    public mutating func setProviderEntry(_ entry: QuotaEntry, for provider: QuotaProvider) {
        setAccounts([], for: provider)
        providerEntries[provider] = entry
    }

    /// Ignored for an Account the board no longer lists, so a fetch that
    /// finishes after its Account vanished cannot bring the row back.
    public mutating func set(_ entry: QuotaEntry, for key: QuotaAccountKey) {
        guard accounts(of: key.provider).contains(where: { $0.key == key }) else { return }
        entries[key] = entry
    }

    public func entry(for key: QuotaAccountKey) -> QuotaEntry {
        entries[key] ?? .loading
    }

    /// Provider order, then Account order. A Provider with one Account reads
    /// exactly as it did before Accounts existed; only several need telling
    /// apart, and their Sources are the one thing safe to show.
    public var rows: [QuotaRowModel] {
        providers.flatMap { provider -> [QuotaRowModel] in
            let found = accounts(of: provider)
            guard !found.isEmpty else {
                return [QuotaRowModel(id: provider.rawValue, provider: provider, title: provider.displayName,
                                      entry: providerEntries[provider] ?? .loading)]
            }
            return found.map { account in
                let title = found.count == 1
                    ? provider.displayName
                    : "\(provider.displayName) · \(account.sources.map(\.rawValue).joined(separator: ", "))"
                return QuotaRowModel(id: "\(provider.rawValue)/\(account.key.id)", provider: provider,
                                     title: title, entry: entry(for: account.key))
            }
        }
    }
}
```

In `Sources/HerdviewCore/UIShotFixtures.swift`, replace the whole `quota(now:)` function with:

```swift
    /// Every Quota state the panel draws: fresh, not signed in, two Accounts of
    /// one Provider (one of them spent), and one quiet Account held by two
    /// Sources.
    public static func quota(now: Date) -> QuotaBoard {
        let hour: TimeInterval = 3_600
        let fiveHours = 5 * hour
        let week = 7 * 24 * hour
        func window(_ label: String, _ used: Double, resetIn: TimeInterval, _ duration: TimeInterval?) -> QuotaWindow {
            QuotaWindow(label: label, usedPercent: used, resetsAt: now.addingTimeInterval(resetIn), duration: duration)
        }
        func account(_ provider: QuotaProvider, _ id: String, _ sources: [QuotaSource]) -> QuotaAccount {
            QuotaAccount(key: QuotaAccountKey(provider: provider, id: id), sources: sources)
        }
        let claude = account(.claude, "claude", [.claude])
        let openCodeOld = account(.opencodeGo, "old", [.opencode])
        let openCodeNew = account(.opencodeGo, "new", [.pi])
        let grok = account(.grok, "grok", [.grok, .pi])

        var board = QuotaBoard(providers: QuotaProvider.allCases)
        board.setAccounts([claude], for: .claude)
        board.set(.ok(QuotaReport(provider: .claude, windows: [
            window("5h", 72, resetIn: 2 * hour + 17 * 60, fiveHours),
            window("week", 65, resetIn: 3 * hour, week),
            window("week · Fable", 0, resetIn: 3 * hour, week),
        ], fetchedAt: now)), for: claude.key)
        board.setProviderEntry(.notSignedIn, for: .codex)
        board.setAccounts([openCodeOld, openCodeNew], for: .opencodeGo)
        board.set(.ok(QuotaReport(provider: .opencodeGo, windows: [
            window("5h", 0, resetIn: 2 * hour, fiveHours),
            window("week", 100, resetIn: 3 * 24 * hour, week),
            window("month", 50, resetIn: 26 * 24 * hour, nil),
        ], fetchedAt: now)), for: openCodeOld.key)
        board.set(.ok(QuotaReport(provider: .opencodeGo, windows: [
            window("5h", 2, resetIn: 3 * hour + 43 * 60, fiveHours),
            window("week", 44, resetIn: 4 * 24 * hour + 11 * hour, week),
            window("month", 22, resetIn: 27 * 24 * hour, nil),
        ], fetchedAt: now)), for: openCodeNew.key)
        board.setAccounts([grok], for: .grok)
        board.set(.problem(.quiet, last: QuotaReport(provider: .grok, windows: [
            window("week", 91, resetIn: 2 * 24 * hour, week),
        ], fetchedAt: now.addingTimeInterval(-3 * hour))), for: grok.key)
        return board
    }
```

- [ ] **Step 3b: Keep the App compiling**

`Sources/App/UIShots.swift` still iterates the old dictionary, and the App's `QuotaStore` is only rewired in Task 5. Until then, replace

```swift
        let quotaStore = QuotaStore(providers: QuotaProvider.allCases, preferences: preferences)
        for (provider, entry) in UIShotFixtures.quota(now: now) {
            quotaStore.set(entry, for: provider)
        }
```

with this temporary shim (the old store holds one entry per Provider, so the second OpenCode Go row overwrites the first; Task 5 replaces the shim with `quotaStore.load(_:)`):

```swift
        let quotaStore = QuotaStore(providers: QuotaProvider.allCases, preferences: preferences)
        for row in UIShotFixtures.quota(now: now).rows {
            quotaStore.set(row.entry, for: row.provider)
        }
```

- [ ] **Step 4: Run the tests and the build**

Run: `swift test 2>&1 | tail -5 && swift build 2>&1 | tail -3`
Expected: `0 failures`, then `Build complete!`.

- [ ] **Step 5: Commit**

```bash
git add Sources/HerdviewCore/QuotaBoard.swift Sources/HerdviewCore/UIShotFixtures.swift Sources/App/UIShots.swift Tests/HerdviewCoreTests/QuotaBoardTests.swift
git commit -m "feat(quota): model the panel as Accounts per Provider"
```

---

### Task 5: Wire the App to Accounts

**Files:**
- Modify: `Sources/App/CredentialReader.swift:19-26`
- Modify: `Sources/App/QuotaStore.swift` (whole file)
- Modify: `Sources/App/QuotaMonitor.swift:36-37`, `:115-135` (`refresh`), `:144-181` (`fetch`)
- Modify: `Sources/App/QuotaRows.swift:13-21`, `:41-51`
- Modify: `Sources/App/QuotaTitleBar.swift:81-86`, `:110`, `:199-200`, `:254-270`
- Modify: `Sources/App/UIShots.swift:52-55`

**Interfaces:**
- Consumes: `QuotaSource.sources(for:)`, `QuotaCredentials.filePath(for source:)`, `QuotaCredentials.parse(_:from:_:)` (Task 1); `QuotaAccounts.group` (Task 2); `QuotaBoard`, `QuotaRowModel` (Task 4); `QuotaProblem.message` (Task 3).
- Produces: `CredentialReader.read(_ provider: QuotaProvider, from source: QuotaSource) async -> CredentialLookup`; `QuotaStore` API: `board`, `rows`, `accounts(of:)`, `entry(for key:)`, `set(_:for key:)`, `setAccounts(_:for:)`, `setProviderEntry(_:for:)`, `load(_:)`, `fetching`, `setFetching(_:for:)`.

No unit tests reach the App target. Verification is the build, the full test suite, `ui:shots`, and the manual check in Step 7.

- [ ] **Step 1: CredentialReader reads one Source**

Replace `read(_:)` in `Sources/App/CredentialReader.swift` with:

```swift
    static func read(_ provider: QuotaProvider, from source: QuotaSource) async -> CredentialLookup {
        if let path = QuotaCredentials.filePath(for: source, home: NSHomeDirectory()) {
            guard let data = FileManager.default.contents(atPath: path),
                  let credential = QuotaCredentials.parse(provider, from: source, data) else { return .notSignedIn }
            return .found(credential)
        }
        return await readClaudeKeychain()
    }
```

- [ ] **Step 2: QuotaStore wraps the board**

Replace the body of `QuotaStore` in `Sources/App/QuotaStore.swift` (keep the imports, `isExpanded`, `preferences`, `refreshAction`, `refreshNow`, `fetching`, `setFetching`) so the file reads:

```swift
import Foundation
import Combine
import HerdviewCore

/// What the Quota strip and panel show: the board of Accounts per Provider.
/// Owned by the main actor; the strip observes it.
@MainActor
final class QuotaStore: ObservableObject {
    /// The Providers to show and fetch, in strip order. Fixed at construction
    /// from the config's `hidden_providers`, so the monitor reads the same list
    /// the panel draws and neither can drift from the other.
    let providers: [QuotaProvider]

    @Published private(set) var board: QuotaBoard

    /// Providers with a fetch in flight, so the strip can show that a refresh
    /// is under way.
    @Published private(set) var fetching: Set<QuotaProvider> = []

    /// Whether the panel is expanded to the full list. Remembered across
    /// launches.
    @Published var isExpanded: Bool {
        didSet { preferences.isQuotaExpanded = isExpanded }
    }

    private let preferences: WindowPreferences

    init(providers: [QuotaProvider], preferences: WindowPreferences = WindowPreferences()) {
        self.providers = providers
        self.preferences = preferences
        board = QuotaBoard(providers: providers)
        isExpanded = preferences.isQuotaExpanded
    }

    /// What the strip's refresh button runs. Set by whoever owns the monitor,
    /// so the strip never holds the monitor itself.
    var refreshAction: (() -> Void)?

    func refreshNow() {
        refreshAction?()
    }

    var rows: [QuotaRowModel] { board.rows }

    func accounts(of provider: QuotaProvider) -> [QuotaAccount] {
        board.accounts(of: provider)
    }

    func entry(for key: QuotaAccountKey) -> QuotaEntry {
        board.entry(for: key)
    }

    func set(_ entry: QuotaEntry, for key: QuotaAccountKey) {
        board.set(entry, for: key)
    }

    func setAccounts(_ accounts: [QuotaAccount], for provider: QuotaProvider) {
        board.setAccounts(accounts, for: provider)
    }

    func setProviderEntry(_ entry: QuotaEntry, for provider: QuotaProvider) {
        board.setProviderEntry(entry, for: provider)
    }

    /// Replaces everything at once. Only the UI shots use it, to draw fixtures.
    func load(_ board: QuotaBoard) {
        self.board = board
    }

    func setFetching(_ isFetching: Bool, for provider: QuotaProvider) {
        if isFetching { fetching.insert(provider) } else { fetching.remove(provider) }
    }
}
```

- [ ] **Step 3: QuotaMonitor fetches per Account**

In `Sources/App/QuotaMonitor.swift`:

Change the property

```swift
    private var rateLimitedUntil: [QuotaProvider: Date] = [:]
```

to

```swift
    /// Per Account: a rate limit on one Account says nothing about another.
    private var rateLimitedUntil: [QuotaAccountKey: Date] = [:]
```

In `refresh(_:)` change `rateLimitedUntil: rateLimitedUntil[provider]` to `rateLimitedUntil: waitUntil(provider)`, and add below `refresh(_:)`:

```swift
    /// When every Account the Provider has is waiting out a rate limit, the
    /// earliest of those; otherwise `nil`, so the others still get fetched.
    private func waitUntil(_ provider: QuotaProvider) -> Date? {
        let limits = store.accounts(of: provider).map { rateLimitedUntil[$0.key] }
        guard !limits.isEmpty, !limits.contains(where: { $0 == nil }) else { return nil }
        return limits.compactMap { $0 }.min()
    }
```

Replace the whole `fetch(_:)` function with:

```swift
    private func fetch(_ provider: QuotaProvider) async {
        var found: [(source: QuotaSource, credential: QuotaCredential)] = []
        var failure: String?
        for source in QuotaSource.sources(for: provider) {
            let lookup = await CredentialReader.read(provider, from: source)
            guard canContinueFetch else { return }
            switch lookup {
            case .found(let credential): found.append((source: source, credential: credential))
            case .notSignedIn: break
            case .failed(let reason): failure = failure ?? reason
            }
        }
        let accounts = QuotaAccounts.group(found, provider: provider)

        if accounts.isEmpty {
            // Visibility can change without cancellation (for example an AppKit
            // order-out notification arriving after the window flag changed).
            guard canContinueFetch else { return }
            guard let failure else {
                store.setProviderEntry(.notSignedIn, for: provider)
                return
            }
            NSLog("herdview: quota %@: failed: %@", provider.rawValue, failure)
            let known = store.accounts(of: provider)
            guard !known.isEmpty else {
                store.setProviderEntry(.problem(.failed(failure), last: nil), for: provider)
                return
            }
            // A Source that could not be read says nothing about the Accounts
            // it held before, so their last numbers stay, dimmed.
            for account in known {
                let entry = store.entry(for: account.key).applying(.failed(failure), provider: provider, now: Date())
                store.set(entry, for: account.key)
            }
            return
        }
        guard canContinueFetch else { return }
        store.setAccounts(accounts.map(\.account), for: provider)

        for (account, credential) in accounts {
            let key = account.key
            if let until = rateLimitedUntil[key], Date() < until { continue }
            // Recheck immediately before the network boundary.
            guard canContinueFetch else { return }
            // `nil` means hidden/stopped/cancelled, not a Provider failure.
            guard let outcome = await request(provider, credential) else { return }

            // Keep each externally visible side effect independently gated. There
            // is no suspension between these checks on the main actor, and the
            // visibility closure also catches order-out before its callback runs.
            if case .rateLimited(let until) = outcome {
                guard canContinueFetch else { return }
                rateLimitedUntil[key] = until
            }
            guard canContinueFetch else { return }
            NSLog("herdview: quota %@ via %@: %@", provider.rawValue,
                  account.sources.map(\.rawValue).joined(separator: ","), outcome.logDescription)
            guard canContinueFetch else { return }
            let entry = store.entry(for: key).applying(outcome, provider: provider, now: Date())
            guard canContinueFetch else { return }
            store.set(entry, for: key)
        }
    }
```

Update the comment in `refresh(_:)` that says "a hidden Provider is one nobody has an account for" only if it no longer reads true; it still does, so leave it.

- [ ] **Step 4: The panel and the strip draw rows**

In `Sources/App/QuotaRows.swift`, in `QuotaRows.body` replace

```swift
            ForEach(Array(store.providers.enumerated()), id: \.element) { index, provider in
```

with

```swift
            ForEach(Array(store.rows.enumerated()), id: \.element.id) { index, row in
```

and

```swift
                QuotaRow(provider: provider, entry: store.entry(for: provider), now: now)
```

with

```swift
                QuotaRow(provider: row.provider, title: row.title, entry: row.entry, now: now)
```

Update the doc comment above `QuotaRows` from "One block per Provider the store lists" to "One block per row the store lists — a Provider, or each of its Accounts". In `QuotaRow` add `let title: String` after `let provider: QuotaProvider`, and change `Text(provider.displayName)` to `Text(title)`.

In `Sources/App/QuotaTitleBar.swift`, in `strip(showPercent:now:)` replace

```swift
            ForEach(store.providers, id: \.self) { provider in
                QuotaMiniGauge(provider: provider,
                               entry: store.entry(for: provider),
                               now: now,
                               showPercent: showPercent)
            }
```

with

```swift
            ForEach(store.rows) { row in
                QuotaMiniGauge(provider: row.provider,
                               title: row.title,
                               entry: row.entry,
                               now: now,
                               showPercent: showPercent)
            }
```

change `QuotaFormat.lastUpdated(store.providers.map(store.entry(for:)))` to `QuotaFormat.lastUpdated(store.rows.map(\.entry))`, add `let title: String` after `let provider: QuotaProvider` in `QuotaMiniGauge`, and in its `help` replace every `provider.displayName` with `title` (four places: `.loading`, `.notSignedIn`, `.problem`, `.ok`).

- [ ] **Step 5: UI shots load the fixture board**

In `Sources/App/UIShots.swift` replace the Task 4 shim

```swift
        let quotaStore = QuotaStore(providers: QuotaProvider.allCases, preferences: preferences)
        for row in UIShotFixtures.quota(now: now).rows {
            quotaStore.set(row.entry, for: row.provider)
        }
```

with

```swift
        let quotaStore = QuotaStore(providers: QuotaProvider.allCases, preferences: preferences)
        quotaStore.load(UIShotFixtures.quota(now: now))
```

- [ ] **Step 6: Build, test, and draw**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!` with no warnings from the changed files.

Run: `mise run ci > /tmp/herdview-ci-$(date +%s).log 2>&1; echo "exit=$?"`, then `rg -n "FAIL|error:|failed" /tmp/herdview-ci-*.log | tail -20`.
Expected: `exit=0`. Open `build/ui-shots/02-expanded-by-click.png` and `05-dark-expanded.png` and check by eye: rows `OpenCode Go · opencode` (week 100%) and `OpenCode Go · pi`, one `Grok` row dimmed with `quiet · updated 3h ago`, and the collapsed strip `01-collapsed.png` has five gauges.

- [ ] **Step 7: Check against this Mac**

Run: `mise run dev`, open the Quota panel, and check:
- two OpenCode Go rows: `· opencode` at week 100%, `· pi` with the new Account's numbers;
- one `Grok` row (grok and pi hold the same Account);
- `log stream --process herdview --predicate 'eventMessage CONTAINS "quota"'` shows `via opencode`, `via pi`, `via grok,pi`, and no token, key or id.

- [ ] **Step 8: Commit**

```bash
git add Sources/App/CredentialReader.swift Sources/App/QuotaStore.swift Sources/App/QuotaMonitor.swift Sources/App/QuotaRows.swift Sources/App/QuotaTitleBar.swift Sources/App/UIShots.swift
git commit -m "feat(quota): fetch and show every Account from every Source"
```

---

### Task 6: Documentation

**Files:**
- Modify: `README.md:108-125`
- Modify: `docs/superpowers/specs/2026-09-24-quota-accounts-design.md` (Flow section)

**Interfaces:** none.

- [ ] **Step 1: README credential table and expiry wording**

In `README.md`, replace the credential table rows and the paragraph after them (lines 110-125, from `| Claude | Keychain item` to `means a Provider changed its API.`) with:

```markdown
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
```

Check the README's line above the table still introduces it correctly (`sed -n 100,112p README.md`); adjust only that sentence if it says "each CLI's credential" to "the credentials these tools keep".

- [ ] **Step 2: Spec matches what was built**

In `docs/superpowers/specs/2026-09-24-quota-accounts-design.md`, replace the paragraph

```markdown
Scheduling, rate-limit waits and cancellation move from per-Provider to per-Account
keys; their rules do not change. A rate limit on one Account does not hold back
another.
```

with

```markdown
Scheduling and cancellation stay per Provider: one fetch reads every Source, then asks
for each Account in turn. Rate-limit waits move to per-Account keys, so a rate limit on
one Account does not hold back another; a Provider is skipped only while every one of
its Accounts is waiting.

Expiry comes from the token itself (JWT `exp`), for every Source alike; pi's
`xai.expires` is not read.
```

- [ ] **Step 3: Verify and commit**

Run: `rg -n "sign-in expired" README.md docs/superpowers/specs/2026-09-24-quota-accounts-design.md` — the only hits are in the spec's Quiet section, quoting the old wording.

```bash
git add README.md docs/superpowers/specs/2026-09-24-quota-accounts-design.md
git commit -m "docs: document Quota per Account and the quiet state"
```
