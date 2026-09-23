import XCTest
@testable import HerdviewCore

final class AgentFilterTests: XCTestCase {
    private func info(paneId: String, agent: String? = nil, cwd: String? = nil,
                      terminalTitleStripped: String? = nil,
                      agentStatus: AgentStatus = .idle) -> AgentInfo {
        AgentInfo(paneId: paneId, workspaceId: "w2", agent: agent,
                  terminalTitleStripped: terminalTitleStripped, cwd: cwd,
                  agentStatus: agentStatus, revision: 1)
    }

    private func tracked(host: String = "dev", session: String = "s", paneId: String = "w2:p1",
                         agent: String? = nil, cwd: String? = nil,
                         terminalTitleStripped: String? = nil,
                         agentStatus: AgentStatus = .idle) -> TrackedAgent {
        TrackedAgent(host: host, session: session,
                     info: info(paneId: paneId, agent: agent, cwd: cwd,
                                terminalTitleStripped: terminalTitleStripped,
                                agentStatus: agentStatus),
                     since: Date())
    }

    func testEmptyQueryAndAllScopeShowsEveryAgent() {
        let agents = [tracked(paneId: "w2:p1", agentStatus: .blocked),
                      tracked(paneId: "w2:p2", agentStatus: .working)]
        let filter = AgentFilter()
        let result = filter.apply(to: agents)
        XCTAssertEqual(result.visible, agents)
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(result.hiddenCount, 0)
    }

    func testWhitespaceOnlyQueryIsNotActive() {
        let filter = AgentFilter(query: " \n\t ")
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.apply(to: [tracked()]).visible.count, 1)
    }

    func testQueryMatchesCwdCaseInsensitively() {
        let agent = tracked(cwd: "/Users/x/herdview")
        XCTAssertTrue(AgentFilter(query: "HERDVIEW").matchesQuery(agent))
    }

    func testQueryMatchesHostSessionAgentKindAndTerminalTitle() {
        XCTAssertTrue(AgentFilter(query: "devtuf").matchesQuery(tracked(host: "devtuf")))
        XCTAssertTrue(AgentFilter(query: "blue-matrix").matchesQuery(tracked(session: "blue-matrix")))
        XCTAssertTrue(AgentFilter(query: "codex").matchesQuery(tracked(agent: "codex")))
        XCTAssertTrue(AgentFilter(query: "forecast")
            .matchesQuery(tracked(terminalTitleStripped: "MME forecast integration")))
    }

    func testQueryIsDiacriticInsensitive() {
        let agent = tracked(terminalTitleStripped: "Phiên lọc")
        XCTAssertTrue(AgentFilter(query: "phien").matchesQuery(agent))
    }

    func testTokensAreAndedAcrossFields() {
        let claudeOnDevtuf = tracked(host: "devtuf", paneId: "w2:p1", agent: "claude")
        let codexOnDevtuf = tracked(host: "devtuf", paneId: "w2:p2", agent: "codex")
        let claudeOnLocal = tracked(host: "local", paneId: "w2:p3", agent: "claude")
        let filter = AgentFilter(query: "devtuf claude")
        XCTAssertTrue(filter.matches(claudeOnDevtuf))
        XCTAssertFalse(filter.matches(codexOnDevtuf))
        XCTAssertFalse(filter.matches(claudeOnLocal))
    }

    func testScopeKeepsOnlyItsStatuses() {
        let blocked = tracked(paneId: "w2:p1", agentStatus: .blocked)
        let done = tracked(paneId: "w2:p2", agentStatus: .done)
        let working = tracked(paneId: "w2:p3", agentStatus: .working)
        let idle = tracked(paneId: "w2:p4", agentStatus: .idle)
        let unknown = tracked(paneId: "w2:p5", agentStatus: .unknown)
        let agents = [blocked, done, working, idle, unknown]
        XCTAssertEqual(AgentFilter(scope: .needsMe).apply(to: agents).visible, [blocked, done])
        XCTAssertEqual(AgentFilter(scope: .working).apply(to: agents).visible, [working])
        XCTAssertEqual(AgentFilter(scope: .idle).apply(to: agents).visible, [idle])
        XCTAssertEqual(AgentFilter(scope: .all).apply(to: agents).visible, agents)
    }

    func testHiddenAskingForAPersonCountsAgentsTheQueryHides() {
        let blocked = tracked(host: "devtuf", paneId: "w2:p1", cwd: "/x/other",
                              agentStatus: .blocked)
        let idle = tracked(host: "local", paneId: "w2:p2", cwd: "/x/herdview", agentStatus: .idle)
        XCTAssertEqual(AgentFilter(query: "herdview").apply(to: [blocked, idle])
            .hiddenAskingForAPerson, 1)
        XCTAssertEqual(AgentFilter(scope: .needsMe).apply(to: [blocked, idle])
            .hiddenAskingForAPerson, 0)
    }

    func testHiddenHostsCountsHostsWithNoVisibleAgent() {
        let hiddenA = tracked(host: "devtuf", paneId: "w2:p1", cwd: "/x/other")
        let hiddenB = tracked(host: "devtuf", paneId: "w2:p2", cwd: "/x/other")
        let visibleA = tracked(host: "local", paneId: "w2:p3", cwd: "/x/herdview")
        let visibleB = tracked(host: "local", paneId: "w2:p4", cwd: "/x/other")
        let result = AgentFilter(query: "herdview")
            .apply(to: [hiddenA, hiddenB, visibleA, visibleB])
        XCTAssertEqual(result.hiddenHosts, 1)
    }

    func testScopeCountsFollowTheQueryButNotTheScope() {
        let blocked = tracked(paneId: "w2:p1", cwd: "/x/herdview", agentStatus: .blocked)
        let idle1 = tracked(paneId: "w2:p2", cwd: "/x/herdview", agentStatus: .idle)
        let idle2 = tracked(paneId: "w2:p3", cwd: "/x/herdview", agentStatus: .idle)
        let result = AgentFilter(query: "herdview", scope: .idle)
            .apply(to: [blocked, idle1, idle2])
        XCTAssertEqual(result.scopeCounts, [.all: 3, .needsMe: 1, .working: 0, .idle: 2])
    }

    func testVisiblePreservesInputOrder() {
        let agents = [tracked(host: "c", paneId: "w2:p1"),
                      tracked(host: "a", paneId: "w2:p2"),
                      tracked(host: "b", paneId: "w2:p3")]
        XCTAssertEqual(AgentFilter().apply(to: agents).visible.map(\.host), ["c", "a", "b"])
    }

    /// A narrow window falls back to these, so each must be a real shortening
    /// that still tells the segments apart.
    func testShortTitlesAreShorterAndStillDistinct() {
        let short = AgentScope.allCases.map(\.shortTitle)
        XCTAssertEqual(Set(short).count, AgentScope.allCases.count)
        for scope in AgentScope.allCases {
            XCTAssertFalse(scope.shortTitle.isEmpty)
            XCTAssertLessThanOrEqual(scope.shortTitle.count, scope.title.count)
        }
        XCTAssertLessThan(short.joined().count, AgentScope.allCases.map(\.title).joined().count)
    }
}
