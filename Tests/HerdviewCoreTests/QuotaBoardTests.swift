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
