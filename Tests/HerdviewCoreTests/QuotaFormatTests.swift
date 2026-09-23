import XCTest
@testable import HerdviewCore

final class QuotaFormatTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_650_000)

    private func until(_ seconds: TimeInterval) -> String? {
        QuotaFormat.untilReset(now.addingTimeInterval(seconds), now: now)
    }

    func testPercentRounds() {
        XCTAssertEqual(QuotaFormat.percent(19), "19%")
        XCTAssertEqual(QuotaFormat.percent(42.5), "43%")
        XCTAssertEqual(QuotaFormat.percent(0), "0%")
    }

    func testUntilReset() {
        XCTAssertEqual(until(4 * 86_400 + 7_200), "4d2h")
        XCTAssertEqual(until(6 * 86_400 + 23 * 3_600 + 59 * 60), "6d23h")
        XCTAssertEqual(until(2 * 86_400), "2d")
        XCTAssertEqual(until(86_400 + 5 * 3_600 + 59), "1d5h")
        XCTAssertEqual(until(86_400), "1d")
        XCTAssertEqual(until(3_600 + 36 * 60), "1h36m")
        XCTAssertEqual(until(5 * 3_600), "5h")
        XCTAssertEqual(until(36 * 60 + 30), "36m")
        XCTAssertEqual(until(59), "<1m")
    }

    func testAResetInThePastIsPending() {
        XCTAssertEqual(until(0), "reset pending")
        XCTAssertEqual(until(-600), "reset pending")
    }

    func testNoResetHasNoText() {
        XCTAssertNil(QuotaFormat.untilReset(nil, now: now))
    }

    func testUpdatedAgo() {
        XCTAssertEqual(QuotaFormat.updatedAgo(now.addingTimeInterval(-30), now: now), "updated just now")
        XCTAssertEqual(QuotaFormat.updatedAgo(now.addingTimeInterval(-23 * 60), now: now), "updated 23m ago")
        XCTAssertEqual(QuotaFormat.updatedAgo(now.addingTimeInterval(-3 * 3_600), now: now), "updated 3h ago")
        XCTAssertEqual(QuotaFormat.updatedAgo(now.addingTimeInterval(-2 * 86_400), now: now), "updated 2d ago")
    }

    // MARK: Elapsed time

    private func elapsed(resetIn seconds: TimeInterval?, duration: TimeInterval?) -> Double? {
        QuotaFormat.elapsedFraction(resetsAt: seconds.map { now.addingTimeInterval($0) },
                                    duration: duration, now: now)
    }

    func testElapsedFractionIsHowFarThroughTheWindowNowIs() {
        XCTAssertEqual(elapsed(resetIn: 3_600, duration: 18_000) ?? -1, 0.8, accuracy: 0.0001)
        XCTAssertEqual(elapsed(resetIn: 18_000, duration: 18_000) ?? -1, 0, accuracy: 0.0001)
    }

    /// A Reset further off than the Window is long, or already past, pins the
    /// marker to an end rather than drawing it outside the bar.
    func testElapsedFractionStaysOnTheBar() {
        XCTAssertEqual(elapsed(resetIn: 20_000, duration: 18_000), 0)
        XCTAssertEqual(elapsed(resetIn: -60, duration: 18_000), 1)
    }

    func testElapsedFractionNeedsAResetAndALength() {
        XCTAssertNil(elapsed(resetIn: nil, duration: 18_000))
        XCTAssertNil(elapsed(resetIn: 3_600, duration: nil))
        XCTAssertNil(elapsed(resetIn: 3_600, duration: 0))
    }

    // MARK: Tone

    private func tone(used: Double, resetIn seconds: TimeInterval?, duration: TimeInterval?) -> QuotaFormat.Tone {
        let window = QuotaWindow(label: "5h", usedPercent: used,
                                 resetsAt: seconds.map { now.addingTimeInterval($0) }, duration: duration)
        return QuotaFormat.tone(of: window, now: now)
    }

    /// 80% of a 5h Window has passed: up to 80% used is on pace, past it is not.
    func testToneIsOnPaceUntilTheBarPassesTheMarker() {
        XCTAssertEqual(tone(used: 30, resetIn: 3_600, duration: 18_000), .onPace)
        XCTAssertEqual(tone(used: 80, resetIn: 3_600, duration: 18_000), .onPace)
        XCTAssertEqual(tone(used: 81, resetIn: 3_600, duration: 18_000), .warning)
        XCTAssertEqual(tone(used: 1, resetIn: 18_000, duration: 18_000), .warning)
    }

    func testToneWarnsNearTheLimitWhateverTheClock() {
        XCTAssertEqual(tone(used: 90, resetIn: 60, duration: 18_000), .warning)
        XCTAssertEqual(tone(used: 95, resetIn: nil, duration: nil), .warning)
    }

    func testToneIsNeutralWithoutAMarker() {
        XCTAssertEqual(tone(used: 50, resetIn: nil, duration: 18_000), .neutral)
        XCTAssertEqual(tone(used: 50, resetIn: 3_600, duration: nil), .neutral)
    }

    // MARK: Summary

    func testSummaryIsTheShortestWindow() {
        let windows = [
            QuotaWindow(label: "week", usedPercent: 28, resetsAt: nil, duration: 604_800),
            QuotaWindow(label: "5h", usedPercent: 19, resetsAt: nil, duration: 18_000),
            QuotaWindow(label: "month", usedPercent: 50, resetsAt: nil),
        ]
        XCTAssertEqual(QuotaFormat.summaryWindow(of: windows)?.label, "5h")
    }

    func testSummaryWithoutAnyLengthIsTheFirstWindow() {
        let windows = [
            QuotaWindow(label: "month", usedPercent: 50, resetsAt: nil),
            QuotaWindow(label: "period", usedPercent: 3, resetsAt: nil),
        ]
        XCTAssertEqual(QuotaFormat.summaryWindow(of: windows)?.label, "month")
        XCTAssertNil(QuotaFormat.summaryWindow(of: []))
    }

    // MARK: Title bar

    private func titleBarLabels(_ windows: [QuotaWindow]) -> [String] {
        QuotaFormat.titleBarWindows(of: windows).map(\.label)
    }

    func testTitleBarShowsTheShortWindowThenThePlainWeek() {
        let windows = [
            QuotaWindow(label: "5h", usedPercent: 19, resetsAt: nil, duration: 18_000),
            QuotaWindow(label: "week", usedPercent: 28, resetsAt: nil, duration: 604_800),
            QuotaWindow(label: "week · Fable", usedPercent: 4, resetsAt: nil, duration: 604_800),
        ]
        XCTAssertEqual(titleBarLabels(windows), ["5h", "week"])
    }

    /// A plain `week` is the one worth the strip even when a per-model 7-day
    /// Window comes first in the report.
    func testTitleBarPrefersThePlainWeekWhereverItSits() {
        let windows = [
            QuotaWindow(label: "week · Fable", usedPercent: 4, resetsAt: nil, duration: 604_800),
            QuotaWindow(label: "5h", usedPercent: 19, resetsAt: nil, duration: 18_000),
            QuotaWindow(label: "week", usedPercent: 28, resetsAt: nil, duration: 604_800),
        ]
        XCTAssertEqual(titleBarLabels(windows), ["5h", "week"])
    }

    func testTitleBarFallsBackToTheFirstSevenDayWindow() {
        let windows = [
            QuotaWindow(label: "5h", usedPercent: 19, resetsAt: nil, duration: 18_000),
            QuotaWindow(label: "week · Fable", usedPercent: 4, resetsAt: nil, duration: 604_800),
        ]
        XCTAssertEqual(titleBarLabels(windows), ["5h", "week · Fable"])
    }

    func testTitleBarDoesNotRepeatTheWeekAsItsOwnSummary() {
        let windows = [QuotaWindow(label: "week", usedPercent: 28, resetsAt: nil, duration: 604_800)]
        XCTAssertEqual(titleBarLabels(windows), ["week"])
    }

    func testTitleBarShowsAWindowWithNoLengthOnItsOwn() {
        let windows = [QuotaWindow(label: "month", usedPercent: 50, resetsAt: nil)]
        XCTAssertEqual(titleBarLabels(windows), ["month"])
    }

    func testTitleBarOfNoWindowsIsEmpty() {
        XCTAssertEqual(titleBarLabels([]), [])
    }
}
