import Foundation

/// One line of the Quota panel, and one gauge of the collapsed strip.
public struct QuotaRowModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let provider: QuotaProvider
    public let title: String
    public let entry: QuotaEntry
}

/// What the Quota panel knows: for each watched Provider either its Accounts
/// with an entry each, or — when no Source holds one — a single entry for the
/// Provider (`.notSignedIn`, or a Source that could not be read).
public struct QuotaBoard: Equatable, Sendable {
    public let providers: [QuotaProvider]
    private var accountsByProvider: [QuotaProvider: [QuotaAccount]] = [:]
    private var providerEntries: [QuotaProvider: QuotaEntry] = [:]
    private var entries: [QuotaAccountKey: QuotaEntry] = [:]

    public init(providers: [QuotaProvider]) {
        self.providers = providers
    }

    public func accounts(of provider: QuotaProvider) -> [QuotaAccount] {
        accountsByProvider[provider] ?? []
    }

    /// The Accounts one read of every Source found. An Account found again
    /// keeps its entry — its sources may have changed, its numbers have not —
    /// and one no longer found goes, entry and all.
    public mutating func setAccounts(_ found: [QuotaAccount], for provider: QuotaProvider) {
        for account in accounts(of: provider) where !found.contains(where: { $0.key == account.key }) {
            entries[account.key] = nil
        }
        accountsByProvider[provider] = found
        providerEntries[provider] = nil
    }

    /// No Source holds an Account for `provider`.
    public mutating func setProviderEntry(_ entry: QuotaEntry, for provider: QuotaProvider) {
        setAccounts([], for: provider)
        providerEntries[provider] = entry
    }

    /// Ignored for an Account the board no longer lists, so a fetch that
    /// finishes after its Account vanished cannot bring the row back.
    public mutating func set(_ entry: QuotaEntry, for key: QuotaAccountKey) {
        guard accounts(of: key.provider).contains(where: { $0.key == key }) else { return }
        entries[key] = entry
    }

    public func entry(for key: QuotaAccountKey) -> QuotaEntry {
        entries[key] ?? .loading
    }

    /// Provider order, then Account order. A Provider with one Account reads
    /// exactly as it did before Accounts existed; only several need telling
    /// apart, and their Sources are the one thing safe to show.
    public var rows: [QuotaRowModel] {
        providers.flatMap { provider -> [QuotaRowModel] in
            let found = accounts(of: provider)
            guard !found.isEmpty else {
                return [QuotaRowModel(id: provider.rawValue, provider: provider, title: provider.displayName,
                                      entry: providerEntries[provider] ?? .loading)]
            }
            return found.map { account in
                let title = found.count == 1
                    ? provider.displayName
                    : "\(provider.displayName) · \(account.sources.map(\.rawValue).joined(separator: ", "))"
                return QuotaRowModel(id: "\(provider.rawValue)/\(account.key.id)", provider: provider,
                                     title: title, entry: entry(for: account.key))
            }
        }
    }
}
