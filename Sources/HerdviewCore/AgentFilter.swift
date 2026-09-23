import Foundation

/// The status slice the list is showing. A scope is the coarse question a person
/// asks of a busy board — "what needs me?", "what is working?" — so the segments
/// read as answers, not as a raw status filter.
public enum AgentScope: String, CaseIterable, Sendable {
    case all
    case needsMe
    case working
    case idle

    /// Whether an agent in this status belongs in the scope. `.all` is the
    /// identity: it keeps every status, including `.unknown`, so an agent whose
    /// status Herdview could not read is never silently dropped from the list.
    public func includes(_ status: AgentStatus) -> Bool {
        switch self {
        case .all: return true
        case .needsMe: return status.asksForAPerson
        case .working: return status == .working
        case .idle: return status == .idle
        }
    }

    /// The labels on the status segments. They are phrased as answers to the
    /// question a person brings to the list, not as raw status names.
    public var title: String {
        switch self {
        case .all: return "All"
        case .needsMe: return "Needs me"
        case .working: return "Working"
        case .idle: return "Idle"
        }
    }
}

/// The search box and status scope together. Kept as one value so the window can
/// hand a single thing to the list and the tests can exercise the whole rule
/// without a view.
public struct AgentFilter: Equatable, Sendable {
    public var query: String
    public var scope: AgentScope

    public init(query: String = "", scope: AgentScope = .all) {
        self.query = query
        self.scope = scope
    }

    /// A non-blank query, or any scope but `.all`. Whitespace alone is not a
    /// search: a stray space must not hide every agent while the box looks empty.
    public var isActive: Bool {
        !tokens.isEmpty || scope != .all
    }

    /// The query split into tokens. Every token has to match, so they are ANDed
    /// rather than ORed: adding a word narrows the list the way a person expects
    /// a search to narrow, and the tokens are free to match different fields —
    /// "devtuf claude" finds a Claude agent on the devtuf host.
    private var tokens: [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Everything a person might name an agent by. The row's own text is searched
    /// too, so what is on screen is always findable, even when it is derived —
    /// the directory's last component, or the title with escapes stripped.
    private func fields(of agent: TrackedAgent) -> [String] {
        let row = AgentTitles.rowText(for: agent)
        return [agent.host, agent.session, agent.info.cwd, agent.info.agent,
                agent.info.displayAgent, agent.info.name, agent.info.terminalTitleStripped,
                row.primary, row.secondary, row.session].compactMap { $0 }
    }

    public func matchesQuery(_ agent: TrackedAgent) -> Bool {
        matchesQuery(agent, tokens: tokens)
    }

    private func matchesQuery(_ agent: TrackedAgent, tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return true }
        let fields = fields(of: agent)
        return tokens.allSatisfy { token in
            fields.contains {
                $0.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    public func matches(_ agent: TrackedAgent) -> Bool {
        matchesQuery(agent) && scope.includes(agent.status)
    }

    public func apply(to agents: [TrackedAgent]) -> AgentFilterResult {
        // Split the query once for the whole batch rather than once per agent.
        let tokens = self.tokens
        var visible: [TrackedAgent] = []
        var hostsWithAVisibleAgent: Set<String> = []
        var inputHosts: Set<String> = []
        var hiddenAskingForAPerson = 0
        var counts: [AgentScope: Int] = [:]
        for scope in AgentScope.allCases { counts[scope] = 0 }

        for agent in agents {
            inputHosts.insert(agent.host)
            let queryMatches = matchesQuery(agent, tokens: tokens)
            // Counts are computed against the query alone, over every scope, so
            // the segments can show what switching to them would give without
            // the current scope hiding the number the switch is about.
            if queryMatches {
                for candidate in AgentScope.allCases where candidate.includes(agent.status) {
                    counts[candidate, default: 0] += 1
                }
            }
            if queryMatches && scope.includes(agent.status) {
                visible.append(agent)
                hostsWithAVisibleAgent.insert(agent.host)
            } else if agent.status.asksForAPerson {
                // The safety rule: if a search or scope hides an agent that is
                // waiting on a person, the banner still has to say so, or the
                // filter would quietly swallow the one thing that needed you.
                hiddenAskingForAPerson += 1
            }
        }

        return AgentFilterResult(
            visible: visible,
            hiddenCount: agents.count - visible.count,
            hiddenHosts: inputHosts.subtracting(hostsWithAVisibleAgent).count,
            hiddenAskingForAPerson: hiddenAskingForAPerson,
            scopeCounts: counts
        )
    }
}

/// What the list shows once the filter has run, plus the numbers the empty state
/// and the segments need. The counts are kept apart from `visible` because they
/// answer different questions: `visible` is the list, the rest is how much the
/// filter is holding back.
public struct AgentFilterResult: Equatable, Sendable {
    /// Input order preserved.
    public let visible: [TrackedAgent]
    public let hiddenCount: Int
    /// Hosts that have at least one agent in the input and none visible.
    public let hiddenHosts: Int
    /// Hidden agents whose status `asksForAPerson` — drives the banner.
    public let hiddenAskingForAPerson: Int
    /// Per scope: how many agents match the query AND that scope.
    /// Counts ignore the current scope so the segments show what switching would give.
    public let scopeCounts: [AgentScope: Int]
}
