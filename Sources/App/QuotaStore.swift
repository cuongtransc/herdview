import Foundation
import Combine
import HerdviewCore

/// What the Quota card shows: one entry per Provider. Owned by the main actor;
/// the card observes it.
@MainActor
final class QuotaStore: ObservableObject {
    /// The Providers to show and fetch, in card order. Fixed at construction
    /// from the config's `hidden_providers`, so the monitor reads the same list
    /// the card draws and neither can drift from the other.
    let providers: [QuotaProvider]

    @Published private(set) var entries: [QuotaProvider: QuotaEntry]

    /// Providers with a fetch in flight, so the card can show that a refresh
    /// is under way.
    @Published private(set) var fetching: Set<QuotaProvider> = []

    /// Whether the card is expanded to the full list. Remembered across
    /// launches.
    @Published var isExpanded: Bool {
        didSet { preferences.isQuotaExpanded = isExpanded }
    }

    private let preferences: WindowPreferences

    init(providers: [QuotaProvider], preferences: WindowPreferences = WindowPreferences()) {
        self.providers = providers
        self.preferences = preferences
        entries = Dictionary(uniqueKeysWithValues: providers.map { ($0, .loading) })
        isExpanded = preferences.isQuotaExpanded
    }

    /// What the card's refresh button runs. Set by whoever owns the monitor,
    /// so the card never holds the monitor itself.
    var refreshAction: (() -> Void)?

    func refreshNow() {
        refreshAction?()
    }

    func entry(for provider: QuotaProvider) -> QuotaEntry {
        entries[provider] ?? .loading
    }

    func set(_ entry: QuotaEntry, for provider: QuotaProvider) {
        entries[provider] = entry
    }

    func setFetching(_ isFetching: Bool, for provider: QuotaProvider) {
        if isFetching { fetching.insert(provider) } else { fetching.remove(provider) }
    }
}
