import Foundation

/// The made-up herd and Quota that `mise run ui:shots` draws the window with.
///
/// The shots are only worth looking at if they are the same every run and show
/// every state the window has to draw, so they come from here rather than from
/// Herdr and the Providers: every Status, a Provider with fresh numbers, one
/// with stale numbers, one with none, a per-model week beside a plain one, and a
/// Window at the warning level. The tests hold the fixtures to that.
public enum UIShotFixtures {
    public static let hosts = ["local", "devtuf"]

    /// Matches idle agents only, so filtering on it hides the blocked one and
    /// the shot shows the banner that says so.
    public static let filterWord = "specs"

    public static func agents() -> [(host: String, session: String, info: AgentInfo)] {
        [
            ("local", "default", agent("w1:p1", "claude", "/Users/dev/herdview", "Filter session and model info", .blocked)),
            ("local", "default", agent("w1:p2", "claude", "/Users/dev/api-gateway", "Refactor rate limiter", .working)),
            ("local", "default", agent("w1:p3", "codex", "/Users/dev/docs-site", "Rewrite install guide", .done)),
            ("local", "ai-tools", agent("w1:p1", "pi", "/Users/dev/vault-specs", "Pro-rata wallet model", .idle)),
            ("devtuf", "default", agent("w1:p1", "claude", "/home/dev/perp-engine", "Backfill funding rates", .working)),
            ("devtuf", "default", agent("w1:p2", "opencode", "/home/dev/perp-specs", "Waiting for input", .idle)),
            ("devtuf", "risk", agent("w2:p1", "claude", "/home/dev/infra", "Terraform plan", .unknown)),
        ]
    }

    public static func quota(now: Date) -> [QuotaProvider: QuotaEntry] {
        let hour: TimeInterval = 3_600
        let fiveHours = 5 * hour
        let week = 7 * 24 * hour
        func window(_ label: String, _ used: Double, resetIn: TimeInterval, _ duration: TimeInterval?) -> QuotaWindow {
            QuotaWindow(label: label, usedPercent: used, resetsAt: now.addingTimeInterval(resetIn), duration: duration)
        }
        return [
            .claude: .ok(QuotaReport(provider: .claude, windows: [
                window("5h", 72, resetIn: 2 * hour + 17 * 60, fiveHours),
                window("week", 65, resetIn: 3 * hour, week),
                window("week · Fable", 0, resetIn: 3 * hour, week),
            ], fetchedAt: now)),
            .codex: .notSignedIn,
            .opencodeGo: .ok(QuotaReport(provider: .opencodeGo, windows: [
                window("5h", 2, resetIn: 3 * hour + 43 * 60, fiveHours),
                window("week", 44, resetIn: 4 * 24 * hour + 11 * hour, week),
                window("month", 22, resetIn: 27 * 24 * hour, nil),
            ], fetchedAt: now)),
            .grok: .problem(.signInExpired, last: QuotaReport(provider: .grok, windows: [
                window("week", 91, resetIn: 2 * 24 * hour, week),
            ], fetchedAt: now.addingTimeInterval(-3 * hour))),
        ]
    }

    private static func agent(_ pane: String, _ kind: String, _ cwd: String, _ title: String,
                              _ status: AgentStatus) -> AgentInfo {
        AgentInfo(paneId: pane, workspaceId: String(pane.prefix(2)), agent: kind,
                  terminalTitle: title, terminalTitleStripped: title, cwd: cwd,
                  agentStatus: status, revision: 1)
    }
}
