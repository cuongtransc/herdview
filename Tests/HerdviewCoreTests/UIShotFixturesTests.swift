import XCTest
@testable import HerdviewCore

final class UIShotFixturesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testTheHerdShowsEveryStatus() {
        let statuses = Set(UIShotFixtures.agents().map(\.info.agentStatus))
        XCTAssertEqual(statuses, Set(AgentStatus.allCases))
    }

    func testEveryAgentSitsOnAFixtureHost() {
        let hosts = Set(UIShotFixtures.agents().map(\.host))
        XCTAssertEqual(hosts, Set(UIShotFixtures.hosts))
    }

    func testAgentsAreUniqueWithinTheirSession() {
        let keys = UIShotFixtures.agents().map { "\($0.host)/\($0.session)/\($0.info.paneId)" }
        XCTAssertEqual(keys.count, Set(keys).count)
    }

    func testEveryProviderHasAnEntry() {
        XCTAssertEqual(Set(UIShotFixtures.quota(now: now).keys), Set(QuotaProvider.allCases))
    }

    func testTheQuotaShowsFreshStaleAndMissingNumbers() {
        let entries = Array(UIShotFixtures.quota(now: now).values)
        XCTAssertTrue(entries.contains { if case .ok = $0 { return true }; return false })
        XCTAssertTrue(entries.contains { if case .problem(_, let last?) = $0 { return !last.windows.isEmpty }; return false })
        XCTAssertTrue(entries.contains { $0 == .notSignedIn })
    }

    func testSomeProviderHasAPerModelWeekBesideItsPlainWeek() {
        let labels = UIShotFixtures.quota(now: now).values.compactMap(\.lastReport).map { $0.windows.map(\.label) }
        XCTAssertTrue(labels.contains { $0.contains("week") && $0.contains { $0.hasPrefix("week · ") } })
    }

    func testSomeWindowIsAtTheWarningLevel() {
        let used = UIShotFixtures.quota(now: now).values.compactMap(\.lastReport).flatMap(\.windows).map(\.usedPercent)
        XCTAssertTrue(used.contains { $0 >= QuotaFormat.warningPercent })
    }

    /// The filter shot needs a word that matches idle agents only, so the
    /// blocked one is hidden and the banner has something to say.
    func testTheFilterWordHidesAnAgentThatAsksForAPerson() {
        let tracked = UIShotFixtures.agents().map {
            TrackedAgent(host: $0.host, session: $0.session, info: $0.info, since: now)
        }
        let result = AgentFilter(query: UIShotFixtures.filterWord).apply(to: tracked)
        XCTAssertFalse(result.visible.isEmpty)
        XCTAssertGreaterThan(result.hiddenAskingForAPerson, 0)
    }
}
