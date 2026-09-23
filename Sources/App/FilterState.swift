import Combine
import HerdviewCore

/// The window's filter as one observable thing, because the search field, the
/// scope segments and the list itself are three views of a single decision.
/// Held apart in each of them, clearing the box in one place would leave the
/// list still filtering on a query nobody can see.
///
/// It also owns the difference between the two halves of the filter: the scope
/// is worth coming back to, so it is written straight through to the stored
/// preferences, while the query is a passing thought and lives only as long as
/// this object does. That is why `scope` persists and `query` does not.
///
/// `focusRequest` exists because ⌘F belongs to the menu, not to the view: the
/// menu item is the only thing that knows the shortcut was pressed, and the
/// field is the only thing that can act on it. A counter bumped by one and
/// watched by the other is the shortest way to hand that intent across without
/// either side reaching into the other.
@MainActor
final class FilterState: ObservableObject {
    @Published var query = ""

    /// The `didSet` does not fire for the assignment made in `init`, which is
    /// exactly right: constructing the state from what was already stored must
    /// not write it back.
    @Published var scope: AgentScope {
        didSet { preferences.agentScope = scope }
    }

    /// Bumped by ⌘F; the view focuses the field whenever it changes.
    @Published private(set) var focusRequest = 0

    private let preferences: WindowPreferences

    /// The single value the list filters with, assembled from both halves so
    /// the caller never has to remember to combine them.
    var filter: AgentFilter { AgentFilter(query: query, scope: scope) }

    init(preferences: WindowPreferences) {
        self.preferences = preferences
        scope = preferences.agentScope
    }

    func requestFocus() {
        focusRequest += 1
    }

    /// Back to showing everything. The scope goes to `.all` rather than to the
    /// stored preference, since clearing a filter means "show me the herd".
    func clear() {
        query = ""
        scope = .all
    }
}
