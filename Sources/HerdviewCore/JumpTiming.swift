import Foundation

/// How long one Jump took, step by step, so a slow Jump can be pinned on the
/// step that was slow rather than guessed at. Written by every Jump to
/// `JumpTimingLog`; `summary(of:)` turns weeks of them into percentiles.
public struct JumpTiming: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// A person asked for it.
        case click
        /// `HERDVIEW_JUMP_BENCH` asked for it.
        case bench
    }

    /// What the Jump did. A failed one stops part way, so its steps are not
    /// comparable with the others'.
    public enum Outcome: Equatable, Sendable {
        case focus
        case open
        case failed(String)
    }

    public struct Step: Codable, Equatable, Sendable {
        public let name: String
        public let ms: Double

        public init(name: String, ms: Double) {
            self.name = name
            self.ms = ms
        }
    }

    public let at: Date
    public let source: Source
    public let outcome: Outcome
    /// cmux terminal tabs open at the time; the `ps` and `tree` costs grow with it.
    public let tabs: Int?
    public let steps: [Step]

    public init(at: Date, source: Source, outcome: Outcome, tabs: Int?, steps: [Step]) {
        self.at = at
        self.source = source
        self.outcome = outcome
        self.tabs = tabs
        self.steps = steps
    }

    public var totalMs: Double { steps.reduce(0) { $0 + $1.ms } }

    private enum CodingKeys: String, CodingKey { case at, source, outcome, error, tabs, steps }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = try c.decode(Date.self, forKey: .at)
        source = try c.decode(Source.self, forKey: .source)
        tabs = try c.decodeIfPresent(Int.self, forKey: .tabs)
        steps = try c.decode([Step].self, forKey: .steps)
        switch try c.decode(String.self, forKey: .outcome) {
        case "focus": outcome = .focus
        case "open": outcome = .open
        default: outcome = .failed(try c.decodeIfPresent(String.self, forKey: .error) ?? "")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(at, forKey: .at)
        try c.encode(source, forKey: .source)
        try c.encodeIfPresent(tabs, forKey: .tabs)
        try c.encode(steps, forKey: .steps)
        switch outcome {
        case .focus: try c.encode("focus", forKey: .outcome)
        case .open: try c.encode("open", forKey: .outcome)
        case .failed(let error):
            try c.encode("failed", forKey: .outcome)
            try c.encode(error, forKey: .error)
        }
    }

    /// Times the steps of one Jump, each from the end of the one before.
    public struct Recorder: Sendable {
        private let now: @Sendable () -> Double
        private var mark: Double
        public private(set) var steps: [Step] = []

        /// `now` is seconds on any monotonic clock.
        public init(now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }) {
            self.now = now
            self.mark = now()
        }

        public mutating func lap(_ name: String) {
            let t = now()
            steps.append(Step(name: name, ms: ((t - mark) * 1000).rounded()))
            mark = t
        }

        /// A step that ended before this Recorder began, such as the click.
        public mutating func prepend(_ name: String, ms: Double) {
            steps.insert(Step(name: name, ms: ms.rounded()), at: 0)
        }

        public var totalMs: Double { steps.reduce(0) { $0 + $1.ms } }
    }

    // MARK: - Summary

    public struct StepSummary: Equatable, Sendable {
        public let name: String
        public let count: Int
        public let p50: Double
        public let p95: Double
        public let max: Double
    }

    public struct Summary: Equatable, Sendable {
        public let jumps: Int
        public let failed: Int
        /// Each step in the order Jumps first ran it, then `total`.
        public let steps: [StepSummary]
    }

    /// Percentiles per step over the Jumps that finished; failed ones are
    /// only counted.
    public static func summary(of records: [JumpTiming]) -> Summary {
        var order: [String] = []
        var values: [String: [Double]] = [:]
        var totals: [Double] = []
        var failed = 0
        for record in records {
            if case .failed = record.outcome {
                failed += 1
                continue
            }
            for step in record.steps {
                if values[step.name] == nil { order.append(step.name) }
                values[step.name, default: []].append(step.ms)
            }
            totals.append(record.totalMs)
        }
        var steps = order.map { stepSummary($0, values[$0] ?? []) }
        if !totals.isEmpty { steps.append(stepSummary("total", totals)) }
        return Summary(jumps: records.count, failed: failed, steps: steps)
    }

    private static func stepSummary(_ name: String, _ values: [Double]) -> StepSummary {
        let sorted = values.sorted()
        return StepSummary(name: name, count: sorted.count,
                           p50: percentile(sorted, 0.50), p95: percentile(sorted, 0.95),
                           max: sorted.last ?? 0)
    }

    /// Nearest rank: the smallest value with at least `q` of them at or below it.
    private static func percentile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((q * Double(sorted.count)).rounded(.up))
        return sorted[Swift.max(0, Swift.min(sorted.count - 1, rank - 1))]
    }

    /// The summary as a table for a terminal.
    public static func report(_ summary: Summary) -> String {
        var lines = ["\(summary.jumps) jumps, \(summary.failed) failed"]
        guard !summary.steps.isEmpty else { return lines[0] }
        let width = Swift.max(4, summary.steps.map(\.name.count).max() ?? 0)
        func pad(_ s: String, _ n: Int) -> String { s.padding(toLength: n, withPad: " ", startingAt: 0) }
        func ms(_ v: Double) -> String { String(repeating: " ", count: Swift.max(0, 7 - "\(Int(v))".count)) + "\(Int(v))" }
        lines.append(pad("step", width) + "      n    p50    p95    max  (ms)")
        for s in summary.steps {
            lines.append(pad(s.name, width) + ms(Double(s.count)) + ms(s.p50) + ms(s.p95) + ms(s.max))
        }
        return lines.joined(separator: "\n")
    }
}

/// Jump timings as JSON Lines, one Jump per line. Bounded: past `maxBytes` the
/// file becomes `<path>.1`, replacing the one before, so at most about twice
/// `maxBytes` is ever kept.
public struct JumpTimingLog: Sendable {
    public static let defaultPath = NSHomeDirectory() + "/.herdview/jump-timings.jsonl"

    public let path: String
    public let maxBytes: Int

    public init(path: String = defaultPath, maxBytes: Int = 1_000_000) {
        self.path = path
        self.maxBytes = maxBytes
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public func append(_ timing: JumpTiming) throws {
        var line = try Self.encoder.encode(timing)
        line.append(0x0A)
        let fm = FileManager.default
        try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let size = (try? fm.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        if size > 0, size + line.count > maxBytes {
            try? fm.removeItem(atPath: path + ".1")
            try fm.moveItem(atPath: path, toPath: path + ".1")
        }
        guard let handle = FileHandle(forWritingAtPath: path) else {
            try line.write(to: URL(fileURLWithPath: path))
            return
        }
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    /// Every Jump kept, oldest first. A line that does not read — a partial
    /// write, a field from a later version — is skipped rather than fatal.
    public func readAll() throws -> [JumpTiming] {
        var records: [JumpTiming] = []
        for file in [path + ".1", path] where FileManager.default.fileExists(atPath: file) {
            let text = try String(contentsOfFile: file, encoding: .utf8)
            for line in text.split(whereSeparator: \.isNewline) {
                if let record = try? Self.decoder.decode(JumpTiming.self, from: Data(line.utf8)) {
                    records.append(record)
                }
            }
        }
        return records
    }
}
