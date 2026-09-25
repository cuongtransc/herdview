import AppKit
import HerdviewCore

// `herdview --jump-stats`: percentiles of the Jumps this Mac has timed, then
// out, without starting the app.
if CommandLine.arguments.contains("--jump-stats") {
    let log = JumpTimingLog()
    do {
        let records = try log.readAll()
        for source in [JumpTiming.Source.click, .bench] {
            let mine = records.filter { $0.source == source }
            guard !mine.isEmpty else { continue }
            print("\(source.rawValue) — \(log.path)")
            print(JumpTiming.report(JumpTiming.summary(of: mine)))
            print()
        }
        if records.isEmpty { print("no Jumps timed yet in \(log.path)") }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("jump-stats: \(log.path): \(error)\n".utf8))
        exit(1)
    }
}

let delegate = MainActor.assumeIsolated { AppDelegate() }
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
