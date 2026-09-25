import Foundation
import Combine
import HerdviewCore

/// Merged view of every watched session. Owned by the main actor; the UI observes it.
@MainActor
final class AgentStore: ObservableObject {
    @Published private(set) var agents: [TrackedAgent] = []
    @Published private(set) var hostOrder: [String] = []
    @Published private(set) var unreachableHosts: Set<String> = []
    @Published var configError: String?

    /// What a double-click on an Agent's row does. Set once the config is read;
    /// nil (the UI shots) makes the double-click do nothing.
    var jumpAction: ((TrackedAgent) -> Void)?
    /// Whether a Jump can reach cmux at all. A session name only turns into a
    /// link when it can: a link that could only fail would be a lie.
    @Published var canJump = false
    /// The Agent whose Jump is running, by `TrackedAgent.key`, so its row can
    /// say so after the pointer has left it.
    @Published var jumpingKey: String?
    /// Why the last Jump failed, shown above the list until it clears itself.
    @Published private(set) var jumpError: String?
    private var jumpErrorClear: Task<Void, Never>?
    /// The socket each watched Session is reached on, by `host/session`: the
    /// Session's own for this Mac, the forwarded one for a remote Host.
    private var socketPaths: [String: String] = [:]

    func setSocketPath(_ path: String?, host: String, session: String) {
        socketPaths["\(host)/\(session)"] = path
    }

    func socketPath(host: String, session: String) -> String? {
        socketPaths["\(host)/\(session)"]
    }

    /// Shows `message` for five seconds; nil clears it at once. A Jump is a
    /// thing that happened, not a state of the herd, so it does not stay.
    func showJumpError(_ message: String?) {
        jumpErrorClear?.cancel()
        jumpError = message
        guard message != nil else { return }
        jumpErrorClear = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.jumpError = nil
        }
    }

    /// Every status change the reducer observed, as it observes it. The list is
    /// a snapshot of what is true now, which is what the window needs; a
    /// transition is a thing that happened once, which is what a notification
    /// needs, and a `@Published` value cannot carry that — a second change
    /// overwrites the first before anyone reads it.
    let transitions = PassthroughSubject<[Transition], Never>()

    private var bySession: [String: [TrackedAgent]] = [:]

    func setHostOrder(_ names: [String]) {
        hostOrder = names
    }

    func apply(host: String, session: String, snapshot: [AgentInfo], now: Date = Date()) {
        let key = "\(host)/\(session)"
        let result = AgentSnapshotReducer.reduce(previous: bySession[key] ?? [], snapshot: snapshot,
                                                 host: host, session: session, now: now)
        bySession[key] = result.agents
        rebuild()
        if !result.transitions.isEmpty {
            transitions.send(result.transitions)
        }
    }

    func removeSession(host: String, session: String) {
        bySession["\(host)/\(session)"] = nil
        rebuild()
    }

    func setReachable(host: String, _ reachable: Bool) {
        if reachable {
            unreachableHosts.remove(host)
        } else {
            unreachableHosts.insert(host)
        }
    }

    func agents(forHost host: String) -> [TrackedAgent] {
        agents.filter { $0.host == host }
    }

    private func rebuild() {
        agents = bySession.values.flatMap { $0 }.sorted(by: AgentOrder.before)
    }
}
