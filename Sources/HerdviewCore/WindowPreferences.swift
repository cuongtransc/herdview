import Foundation

/// The handful of window choices the user makes with the mouse and expects to
/// find again next launch. The window's frame is already remembered by AppKit's
/// own autosave; this covers what AppKit does not, starting with whether the
/// window floats above other apps.
public struct WindowPreferences {
    private static let alwaysOnTopKey = "herdview.alwaysOnTop"
    private static let quotaExpandedKey = "herdview.quotaExpanded"
    private static let agentScopeKey = "herdview.agentScope"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Off until the user asks for it: a window that covers other apps is a
    /// surprise to be opted into, not a default.
    public var isAlwaysOnTop: Bool {
        get { defaults.bool(forKey: Self.alwaysOnTopKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.alwaysOnTopKey) }
    }

    /// Collapsed until the user asks for the full list: the title bar strip
    /// already answers "can I keep going", and the list below is the window's
    /// main job.
    public var isQuotaExpanded: Bool {
        get { defaults.bool(forKey: Self.quotaExpandedKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.quotaExpandedKey) }
    }

    /// The status scope is worth returning to, but a typed search is not: a
    /// query is a passing thought and remembering it would come back next
    /// launch to filter the list the user meant to see in full.
    public var agentScope: AgentScope {
        get { AgentScope(rawValue: defaults.string(forKey: Self.agentScopeKey) ?? "") ?? .all }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.agentScopeKey) }
    }
}
