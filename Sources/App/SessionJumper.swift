import AppKit
import HerdviewCore

/// Brings an Agent to the front: its pane focused inside Herdr, and the cmux
/// tab attached to its Session forward — or a new tab attached to it.
///
/// One Jump at a time. A double-click that lands while the last one is still
/// asking cmux would otherwise see no tab yet and open a second one.
@MainActor
final class SessionJumper {
    private static let timeoutSeconds: Double = 5
    private static let cmuxBundleId = "com.cmuxterm.app"
    private static let ps = HostCommand(executable: "/bin/ps", arguments: ["-axo", "pid=,tty=,command="])

    private enum JumpError: Error, CustomStringConvertible {
        case cmux(String, String)
        var description: String {
            switch self {
            case .cmux(let command, let detail): return "cmux \(command): \(detail)"
            }
        }
    }

    private let hosts: [String: HostConfig]
    private let cmuxPath: String?
    private let store: AgentStore
    private var running = false

    init(hosts: [HostConfig], cmuxPath: String?, store: AgentStore) {
        self.hosts = Dictionary(hosts.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        self.cmuxPath = cmuxPath
        self.store = store
    }

    func jump(_ agent: TrackedAgent) {
        guard !running, let host = hosts[agent.host] else { return }
        guard let cmux = cmuxPath else {
            store.showJumpError("cmux not found — set cmux_path in \(ConfigLoader.defaultPath)")
            return
        }
        running = true
        store.jumpingKey = agent.key
        store.showJumpError(nil)
        let socketPath = store.socketPath(host: agent.host, session: agent.session)
        Task {
            defer {
                running = false
                store.jumpingKey = nil
            }
            await focusPane(agent, socketPath: socketPath)
            do {
                try await bringSessionForward(host: host, session: agent.session, cmux: cmux)
                activateCmux()
            } catch {
                store.showJumpError(String(describing: error))
            }
        }
    }

    /// Best effort: the Agent may have exited since the list was drawn, and
    /// landing in its Session still beats landing nowhere.
    private func focusPane(_ agent: TrackedAgent, socketPath: String?) async {
        guard let socketPath else { return }
        let paneId = agent.info.paneId
        let outcome = await Task.detached(priority: .userInitiated) {
            Result { try HerdrClient.agentFocus(socketPath: socketPath, paneId: paneId) }
        }.value
        if case .failure(let error) = outcome {
            NSLog("herdview: agent.focus %@ failed: %@", agent.key, String(describing: error))
        }
    }

    private func bringSessionForward(host: HostConfig, session: String, cmux: String) async throws {
        // Side by side: each takes about a quarter second and neither needs
        // the other. Without a process list no tab can be recognised; a new
        // tab is still a Jump.
        async let processes = try? ProcessRunner.run(Self.ps, timeoutSeconds: Self.timeoutSeconds)
        let layout = try CmuxLayout.parse(tree: try await run(CmuxCommand.tree(cmux: cmux), label: "tree"))
        let psOutput = await processes
        let clients = AttachClient.parse(ps: psOutput.flatMap { String(data: $0, encoding: .utf8) } ?? "")
        switch Jump.route(host: host, session: session, clients: clients, layout: layout) {
        case .focus(let surface):
            _ = try await run(CmuxCommand.focus(cmux: cmux, surface: surface), label: "focus-panel")
        case .open:
            let attach = HostCommand.attach(for: host, session: session).shellLine
            _ = try await run(CmuxCommand.open(cmux: cmux, layout: layout, command: attach), label: "new-surface")
        }
    }

    private func run(_ command: HostCommand, label: String) async throws -> Data {
        do {
            return try await ProcessRunner.run(command, timeoutSeconds: Self.timeoutSeconds)
        } catch let error as ProcessRunnerError {
            switch error {
            case .launchFailed(let why):
                throw JumpError.cmux(label, why)
            case .nonZeroExit(let code, let stderr):
                throw JumpError.cmux(label, CmuxCommand.failure(stderr: stderr, exitCode: code))
            }
        }
    }

    /// cmux has just been told what to show; this puts it in front of Herdview.
    private func activateCmux() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.cmuxBundleId) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error { NSLog("herdview: could not activate cmux: %@", String(describing: error)) }
        }
    }
}
