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
    public static func route(host: HostConfig, session: String,
                             clients: [AttachClient], layout: CmuxLayout) -> JumpRoute {
        let ttys = Set(clients.filter { $0.session == session && $0.sshTarget == host.ssh }.map(\.tty))
        let tabs = layout.surfaces.filter { ttys.contains($0.tty) }
        guard let first = tabs.first else { return .open }
        return .focus(tabs.first { $0.windowRef == layout.activeWindow } ?? first)
    }
}
