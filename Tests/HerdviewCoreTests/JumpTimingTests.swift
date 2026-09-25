import XCTest
@testable import HerdviewCore

final class JumpTimingTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("jump-timing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func record(_ steps: [(String, Double)], outcome: JumpTiming.Outcome = .focus, error: String? = nil,
                        at seconds: TimeInterval = 0) -> JumpTiming {
        JumpTiming(at: Date(timeIntervalSince1970: 1_790_000_000 + seconds), source: .click, outcome: outcome,
                   error: error, tabs: 42, steps: steps.map { JumpTiming.Step(name: $0.0, ms: $0.1) })
    }

    // MARK: - Recorder

    func testRecorderTimesEachStepFromTheLastAndTotalsThem() {
        var clock: Double = 0
        var recorder = JumpTiming.Recorder(now: { clock })
        clock = 0.020
        recorder.lap("focus pane")
        clock = 0.270
        recorder.lap("cmux tree")
        XCTAssertEqual(recorder.steps.map(\.name), ["focus pane", "cmux tree"])
        XCTAssertEqual(recorder.steps.map(\.ms), [20, 250])
        XCTAssertEqual(recorder.totalMs, 270)
    }

    // MARK: - Log

    func testAppendWritesOneJSONLinePerJumpThatReadsBack() throws {
        let log = JumpTimingLog(path: directory.appendingPathComponent("t.jsonl").path)
        let first = record([("cmux tree", 221.5)])
        let second = record([("ps", 300)], outcome: .failed, error: "cmux tree: denied", at: 5)
        try log.append(first)
        try log.append(second)

        let text = try String(contentsOfFile: log.path, encoding: .utf8)
        XCTAssertEqual(text.split(separator: "\n").count, 2)
        XCTAssertEqual(try log.readAll(), [first, second])
    }

    func testAppendRotatesPastTheCapKeepingOneOlderFile() throws {
        let path = directory.appendingPathComponent("t.jsonl").path
        let log = JumpTimingLog(path: path, maxBytes: 200)
        for i in 0..<6 { try log.append(record([("cmux tree", Double(i))], at: Double(i))) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: path + ".1"))
        let size = try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int ?? .max
        XCTAssertLessThanOrEqual(size, 200 + 200)
        // The newest record is never the one rotated away.
        XCTAssertEqual(try log.readAll().last?.steps.first?.ms, 5)
    }

    func testReadAllSkipsLinesItCannotRead() throws {
        let log = JumpTimingLog(path: directory.appendingPathComponent("t.jsonl").path)
        try log.append(record([("ps", 1)]))
        let handle = try XCTUnwrap(FileHandle(forWritingAtPath: log.path))
        handle.seekToEndOfFile()
        handle.write(Data("not json\n".utf8))
        try handle.close()
        try log.append(record([("ps", 2)], at: 1))

        XCTAssertEqual(try log.readAll().map { $0.steps[0].ms }, [1, 2])
    }

    func testReadAllOfNoFileIsEmpty() throws {
        XCTAssertEqual(try JumpTimingLog(path: directory.appendingPathComponent("none.jsonl").path).readAll(), [])
    }

    // MARK: - Summary

    func testSummaryGivesPercentilesPerStepInFirstSeenOrder() {
        let records = (1...10).map { i in
            record([("cmux tree", Double(i * 10)), ("ps", Double(i))], at: Double(i))
        } + [record([("cmux tree", 999)], outcome: .failed, error: "x", at: 11)]

        let summary = JumpTiming.summary(of: records)
        XCTAssertEqual(summary.jumps, 11)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.steps.map(\.name), ["cmux tree", "ps", "total"])
        let tree = summary.steps[0]
        // Failed Jumps are counted, not timed: they stop part way.
        XCTAssertEqual(tree.count, 10)
        XCTAssertEqual(tree.p50, 50)
        XCTAssertEqual(tree.p95, 100)
        XCTAssertEqual(tree.max, 100)
        XCTAssertEqual(summary.steps[2].p50, 55)
    }

    func testReportIsATableOfTheSummary() {
        let summary = JumpTiming.summary(of: [record([("cmux tree", 221.6), ("ps", 12)])])
        XCTAssertEqual(JumpTiming.report(summary), """
        1 jumps, 0 failed
        step           n    p50    p95    max  (ms)
        cmux tree      1    221    221    221
        ps             1     12     12     12
        total          1    233    233    233
        """)
        XCTAssertEqual(JumpTiming.report(JumpTiming.summary(of: [])), "0 jumps, 0 failed")
    }

    func testSummaryOfNothingIsEmpty() {
        let summary = JumpTiming.summary(of: [])
        XCTAssertEqual(summary.jumps, 0)
        XCTAssertEqual(summary.steps, [])
    }
}
