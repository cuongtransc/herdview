import XCTest
@testable import HerdviewCore

/// The names `hidden_providers` accepts. A hand-written config should not have
/// to know that `opencodeGo` is spelled without a space anywhere else.
final class QuotaProviderTests: XCTestCase {
    func testANameIsFoundHoweverItIsSpelt() {
        XCTAssertEqual(QuotaProvider(name: "codex"), .codex)
        XCTAssertEqual(QuotaProvider(name: "Codex"), .codex)
        XCTAssertEqual(QuotaProvider(name: "CODEX"), .codex)
        XCTAssertEqual(QuotaProvider(name: "claude"), .claude)
        XCTAssertEqual(QuotaProvider(name: "grok"), .grok)
        XCTAssertEqual(QuotaProvider(name: "opencodeGo"), .opencodeGo)
        XCTAssertEqual(QuotaProvider(name: "opencode-go"), .opencodeGo)
        XCTAssertEqual(QuotaProvider(name: "opencode_go"), .opencodeGo)
        XCTAssertEqual(QuotaProvider(name: "OpenCode Go"), .opencodeGo)
    }

    func testNothingElseIsAProvider() {
        XCTAssertNil(QuotaProvider(name: ""))
        XCTAssertNil(QuotaProvider(name: "   "))
        XCTAssertNil(QuotaProvider(name: "gpt5"))
        XCTAssertNil(QuotaProvider(name: "codex2"))
        // The suffix is not a prefix match: `opencode` is not `opencodeGo`.
        XCTAssertNil(QuotaProvider(name: "opencode"))
    }

    func testBothNamesTheAppUsesAreNamesTheConfigAccepts() {
        for provider in QuotaProvider.allCases {
            XCTAssertEqual(QuotaProvider(name: provider.rawValue), provider)
            XCTAssertEqual(QuotaProvider(name: provider.displayName), provider)
        }
    }
}
