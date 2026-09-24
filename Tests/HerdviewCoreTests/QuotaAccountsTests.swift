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
