import Foundation

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

/// What the Quota card knows about one Provider.
public enum QuotaEntry: Equatable, Sendable {
    /// Before the first fetch has finished.
    case loading
    case notSignedIn
    case ok(QuotaReport)
    /// `last` is the most recent successful report, however old: an expired
    /// sign-in means the CLI has not run, so its Quota has not moved either.
    case problem(QuotaProblem, last: QuotaReport?)

    public var lastReport: QuotaReport? {
        switch self {
        case .ok(let report): return report
        case .problem(_, let last): return last
        case .loading, .notSignedIn: return nil
        }
    }

    /// The entry once a fetch has come to `outcome`.
    public func applying(_ outcome: QuotaOutcome, provider: QuotaProvider, now: Date) -> QuotaEntry {
        switch outcome {
        case .report(let windows):
            return .ok(QuotaReport(provider: provider, windows: windows, fetchedAt: now))
        case .signInExpired:
            return .problem(.quiet, last: lastReport)
        case .noSubscription:
            return .problem(.noSubscription, last: nil)
        case .rateLimited:
            return .problem(.rateLimited, last: lastReport)
        case .failed(let reason):
            return .problem(.failed(reason), last: lastReport)
        }
    }
}

/// When a Provider is fetched. Only while the window is visible: every
/// `pollInterval` on the tick, at once when the window is shown but not more
/// than once every `showDebounce`, and at once when the user asks. A rate
/// limit is waited out whatever the trigger.
public enum QuotaSchedule {
    public static let pollInterval: TimeInterval = 5 * 60
    public static let showDebounce: TimeInterval = 60

    public enum Trigger: Sendable {
        case tick
        case shown
        case manual
    }

    public static func isDue(_ trigger: Trigger, lastStarted: Date?, rateLimitedUntil: Date?, now: Date) -> Bool {
        if let until = rateLimitedUntil, now < until { return false }
        guard let last = lastStarted else { return true }
        let gap: TimeInterval
        switch trigger {
        case .tick: gap = pollInterval
        case .shown: gap = showDebounce
        case .manual: return true
        }
        return now.timeIntervalSince(last) >= gap
    }
}
