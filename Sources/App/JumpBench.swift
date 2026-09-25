import AppKit
import HerdviewCore

/// `mise run bench:jump`: the real app, Jumping to one Agent over and over
/// with no one clicking, then printing how long each step took.
///
/// It drives the same `SessionJumper` a double-click does, so what it measures
/// is what a person waits for — except the click itself, which a bench has
/// none of. It moves the screen to cmux on every Jump; that is the point.
@MainActor
enum JumpBench {
    static let environmentKey = "HERDVIEW_JUMP_BENCH"
    static let countKey = "HERDVIEW_JUMP_BENCH_COUNT"

    /// `host` or `host/session`, when this launch is a bench run.
    static var target: String? {
        ProcessInfo.processInfo.environment[environmentKey].flatMap { $0.isEmpty ? nil : $0 }
    }

    private static var count: Int {
        ProcessInfo.processInfo.environment[countKey].flatMap(Int.init).map { max(1, $0) } ?? 5
    }

    /// Waits for the target's first Agent, Jumps `count` times with a pause
    /// between, prints the summary and exits: 0 when every Jump finished.
    static func run(target: String, store: AgentStore, jumper: SessionJumper) {
        let parts = target.split(separator: "/", maxSplits: 1).map(String.init)
        let host = parts[0]
        let session = parts.count > 1 ? parts[1] : nil
        let count = self.count
        let log = JumpTimingLog()
        Task { @MainActor in
            let started = Date()
            var agent: TrackedAgent?
            for _ in 0..<60 {
                agent = store.agents.first { $0.host == host && (session == nil || $0.session == session) }
                if agent != nil { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard let agent else {
                FileHandle.standardError.write(Data("jump-bench: no agent on \(target) after 30 s\n".utf8))
                exit(2)
            }
            print("jump-bench: \(count) jumps to \(agent.host)/\(agent.session) pane \(agent.info.paneId)")
            for i in 1...count {
                guard let jump = jumper.jump(agent, source: .bench) else {
                    FileHandle.standardError.write(Data("jump-bench: jump \(i) did not start\n".utf8))
                    exit(2)
                }
                await jump.value
                // Hand the screen back so the next Jump brings cmux forward again.
                NSApp.activate(ignoringOtherApps: true)
                try? await Task.sleep(for: .milliseconds(1500))
            }
            let mine = ((try? log.readAll()) ?? []).filter { $0.source == .bench && $0.at >= started }
            let summary = JumpTiming.summary(of: mine)
            print(JumpTiming.report(summary))
            exit(summary.failed == 0 && summary.jumps == count ? 0 : 1)
        }
    }
}
