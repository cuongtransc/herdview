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
