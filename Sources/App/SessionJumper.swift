import AppKit
import HerdviewCore

/// Brings an Agent to the front: its pane focused inside Herdr, and the cmux
/// tab attached to its Session forward — or a new tab attached to it.
///
/// One Jump at a time. A double-click that lands while the last one is still
/// asking cmux would otherwise see no tab yet and open a second one.
///
/// Every Jump appends its step timings to `JumpTimingLog`; `herdview
/// --jump-stats` reads them back as percentiles.
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

    /// How long a Jump waits to see cmux come to the front before it stops
    /// timing that step; past it the step is left out, not recorded as slow.
    private static let frontmostTimeout: Duration = .seconds(5)

    private let hosts: [String: HostConfig]
    private let cmuxPath: String?
    private let store: AgentStore
    private let timingLog: JumpTimingLog
    /// The tab each Session was last opened in, for a tab cmux gives no tty.
    private var tabs: JumpTabs
    private var running = false

    init(hosts: [HostConfig], cmuxPath: String?, store: AgentStore, timingLog: JumpTimingLog = JumpTimingLog()) {
        self.hosts = Dictionary(hosts.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        self.cmuxPath = cmuxPath
        self.store = store
        self.timingLog = timingLog
        self.tabs = JumpTabs.load()
    }

    /// Starts a Jump; the returned task ends once its timing is written, which
    /// is after cmux came to the front or `frontmostTimeout`. Nil when no Jump
    /// started. The next Jump can start before then.
    @discardableResult
    func jump(_ agent: TrackedAgent, source: JumpTiming.Source = .click) -> Task<Void, Never>? {
        let clickMs = source == .click ? Self.clickAgeMs() : nil
        guard !running, let host = hosts[agent.host] else { return nil }
        guard let cmux = cmuxPath else {
            store.showJumpError("cmux not found — set cmux_path in \(ConfigLoader.defaultPath)")
            return nil
        }
        running = true
        store.jumpingKey = agent.key
        store.showJumpError(nil)
        let socketPath = store.socketPath(host: agent.host, session: agent.session)
        return Task {
            var recorder = JumpTiming.Recorder()
            if let clickMs { recorder.prepend("click", ms: clickMs) }
            await focusPane(agent, socketPath: socketPath)
            recorder.lap("focus pane")
            var outcome = JumpTiming.Outcome.failed
            var failure: String?
            var tabs: Int?
            var activated = false
            do {
                let result = try await bringSessionForward(host: host, session: agent.session, cmux: cmux,
                                                           recorder: &recorder)
                outcome = result.outcome
                tabs = result.tabs
                activateCmux()
                activated = true
            } catch {
                outcome = .failed
                failure = String(describing: error)
                store.showJumpError(String(describing: error))
            }
            running = false
            store.jumpingKey = nil
            if activated, await waitForCmuxInFront() { recorder.lap("cmux to front") }
            let timing = JumpTiming(at: Date(), source: source, outcome: outcome, error: failure, tabs: tabs, steps: recorder.steps)
            let log = timingLog
            await Task.detached(priority: .utility) {
                do { try log.append(timing) } catch {
                    NSLog("herdview: could not write %@: %@", log.path, String(describing: error))
                }
            }.value
        }
    }

    /// From the click that started this Jump to now, when AppKit is handling
    /// that click; nil for anything else, such as a key press.
    private static func clickAgeMs() -> Double? {
        guard let event = NSApp.currentEvent,
              [.leftMouseDown, .leftMouseUp].contains(event.type) else { return nil }
        return (ProcessInfo.processInfo.systemUptime - event.timestamp) * 1000
    }

    /// True once cmux is the active app, false after `frontmostTimeout`.
    private func waitForCmuxInFront() async -> Bool {
        let deadline = ContinuousClock.now + Self.frontmostTimeout
        while ContinuousClock.now < deadline {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.cmuxBundleId { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
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

    private func bringSessionForward(host: HostConfig, session: String, cmux: String,
                                     recorder: inout JumpTiming.Recorder) async throws -> (outcome: JumpTiming.Outcome, tabs: Int) {
        // Side by side: each takes about a quarter second and neither needs
        // the other. Without a process list no tab can be recognised; a new
        // tab is still a Jump.
        async let processes = try? ProcessRunner.run(Self.ps, timeoutSeconds: Self.timeoutSeconds)
        let layout = try CmuxLayout.parse(tree: try await run(CmuxCommand.tree(cmux: cmux), label: "tree"))
        recorder.lap("cmux tree")
        let psOutput = await processes
        // Only what is left of ps once the tree is in: the two run side by side.
        recorder.lap("ps wait")
        let clients = AttachClient.parse(ps: psOutput.flatMap { String(data: $0, encoding: .utf8) } ?? "")
        let remembered = tabs.surface(host: host.name, session: session)
        switch Jump.route(host: host, session: session, clients: clients, layout: layout, remembered: remembered) {
        case .focus(let surface):
            _ = try await run(CmuxCommand.focus(cmux: cmux, surface: surface), label: "focus-panel")
            recorder.lap("cmux focus-panel")
            return (.focus, layout.surfaces.count)
        case .open:
            let attach = HostCommand.attach(for: host, session: session).shellLine
            let output = try await run(CmuxCommand.open(cmux: cmux, layout: layout, command: attach), label: "new-surface")
            recorder.lap("cmux new-surface")
            if let opened = CmuxCommand.openedSurfaceId(output: String(decoding: output, as: UTF8.self)) {
                tabs.remember(opened, host: host.name, session: session)
                saveTabs()
            } else if remembered != nil {
                // The tab it remembered is closed; a stale id only costs a lookup, but it is wrong.
                tabs.forget(host: host.name, session: session)
                saveTabs()
            }
            return (.open, layout.surfaces.count)
        }
    }

    private func saveTabs() {
        do { try tabs.save() } catch {
            NSLog("herdview: could not write %@: %@", tabs.path, String(describing: error))
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
