import Foundation

/// How a Jump brings a Session forward in cmux.
public enum JumpRoute: Equatable, Sendable {
    /// A tab is already attached to the Session: focus it.
    case focus(CmuxSurface)
    /// No tab is: open one attached to it.
    case open
}

public enum Jump {
    /// Finds the cmux tab attached to `session` on `host`. A client matches
    /// only on the same Host: a local Host takes local clients, a remote one
    /// takes clients whose ssh target is the Host's `ssh` exactly, so a
    /// `default` Session on one machine never answers for another's. With
    /// several tabs, the one in the window the person is looking at wins.
    ///
    /// With no tab found that way, `remembered` — the id of the tab Herdview
    /// last opened for this Session — is focused if cmux still has it: cmux
    /// reports no tty for the tabs it opens, so they are never found by one.
    public static func route(host: HostConfig, session: String,
                             clients: [AttachClient], layout: CmuxLayout,
                             remembered: String? = nil) -> JumpRoute {
        let ttys = Set(clients.filter { $0.session == session && $0.sshTarget == host.ssh }.map(\.tty))
        let tabs = layout.surfaces.filter { $0.tty.map(ttys.contains) ?? false }
        if let first = tabs.first {
            return .focus(tabs.first { $0.windowRef == layout.activeWindow } ?? first)
        }
        if let remembered, let tab = layout.surfaces.first(where: { $0.id == remembered }) {
            return .focus(tab)
        }
        return .open
    }
}
