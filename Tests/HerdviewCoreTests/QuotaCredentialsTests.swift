import XCTest
@testable import HerdviewCore

final class QuotaCredentialsTests: XCTestCase {
    private func parse(_ provider: QuotaProvider, _ json: String) -> QuotaCredential? {
        QuotaCredentials.parse(provider, Data(json.utf8))
    }

    func testClaudeReadsTheAccessTokenFromTheKeychainJSON() {
        let json = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat","refreshToken":"r","expiresAt":1}}"#
        XCTAssertEqual(parse(.claude, json), QuotaCredential(token: "sk-ant-oat"))
    }

    func testCodexReadsTokenAndAccount() {
        let json = #"{"auth_mode":"chatgpt","tokens":{"access_token":"eyJ","account_id":"acct-1","refresh_token":"r"}}"#
        XCTAssertEqual(parse(.codex, json), QuotaCredential(token: "eyJ", accountId: "acct-1"))
    }

    func testCodexWithoutAccountStillHasAToken() {
        let json = #"{"tokens":{"access_token":"eyJ"}}"#
        XCTAssertEqual(parse(.codex, json), QuotaCredential(token: "eyJ", accountId: nil))
    }

    /// An API-key login leaves `tokens` out; that is not a plan with a Quota.
    func testCodexWithAnAPIKeyOnlyIsNotSignedIn() {
        XCTAssertNil(parse(.codex, #"{"OPENAI_API_KEY":"sk-proj"}"#))
    }

    /// OpenCode's file holds every provider it knows; only the Go key matters.
    func testOpenCodeGoReadsOnlyTheGoKey() {
        let json = #"{"nvidia":{"type":"api","key":"nv"},"opencode-go":{"type":"api","key":"go-key"}}"#
        XCTAssertEqual(parse(.opencodeGo, json), QuotaCredential(token: "go-key"))
        XCTAssertNil(parse(.opencodeGo, #"{"nvidia":{"type":"api","key":"nv"}}"#))
    }

    func testGrokPrefersXAIsIssuerWithAnIdSuffix() {
        let json = #"""
        {"https://other.example":{"key":"other","user_id":"u0"},
         "https://auth.x.ai::b1a0":{"key":"xai","user_id":"u1"}}
        """#
        XCTAssertEqual(parse(.grok, json), QuotaCredential(token: "xai", accountId: "u1"))
    }

    func testGrokFallsBackToAnotherIssuer() {
        let json = #"{"https://other.example":{"key":"other"}}"#
        XCTAssertEqual(parse(.grok, json), QuotaCredential(token: "other", accountId: nil))
    }

    func testEmptyTokensAndMalformedFilesAreNotSignedIn() {
        XCTAssertNil(parse(.claude, #"{"claudeAiOauth":{"accessToken":""}}"#))
        XCTAssertNil(parse(.codex, "not json"))
        XCTAssertNil(parse(.grok, "[]"))
    }

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
}
