import XCTest
@testable import HerdviewCore

final class QuotaEntryTests: XCTestCase {
    private let then = Date(timeIntervalSince1970: 1_789_650_000)
    private let now = Date(timeIntervalSince1970: 1_789_651_000)
    private let windows = [QuotaWindow(label: "week", usedPercent: 28, resetsAt: nil)]

    private var ok: QuotaEntry {
        .ok(QuotaReport(provider: .claude, windows: windows, fetchedAt: then))
    }

    func testAReportReplacesWhateverWasThere() {
        let fresh = [QuotaWindow(label: "week", usedPercent: 30, resetsAt: nil)]
        for start in [QuotaEntry.loading, .notSignedIn, ok, .problem(.rateLimited, last: nil)] {
            XCTAssertEqual(start.applying(.report(fresh), provider: .claude, now: now),
                           .ok(QuotaReport(provider: .claude, windows: fresh, fetchedAt: now)))
        }
    }

    /// The last numbers survive every problem that says nothing about them.
    func testProblemsKeepTheLastReport() {
        let last = QuotaReport(provider: .claude, windows: windows, fetchedAt: then)
        XCTAssertEqual(ok.applying(.signInExpired, provider: .claude, now: now), .problem(.quiet, last: last))
        XCTAssertEqual(ok.applying(.rateLimited(until: now), provider: .claude, now: now), .problem(.rateLimited, last: last))
        XCTAssertEqual(ok.applying(.failed("HTTP 500"), provider: .claude, now: now), .problem(.failed("HTTP 500"), last: last))

        let failedTwice = ok.applying(.failed("HTTP 500"), provider: .claude, now: now)
            .applying(.signInExpired, provider: .claude, now: now)
        XCTAssertEqual(failedTwice, .problem(.quiet, last: last))
    }

    /// Without a subscription there is no Quota, so old numbers would be wrong.
    func testNoSubscriptionDropsTheLastReport() {
        XCTAssertEqual(ok.applying(.noSubscription, provider: .opencodeGo, now: now), .problem(.noSubscription, last: nil))
    }

    /// An expired credential asks nothing of the user: no Source has used the
    /// Account lately, so there is nothing to do and the numbers still hold.
    func testMessages() {
        XCTAssertEqual(QuotaProblem.quiet.message, "quiet")
        XCTAssertEqual(QuotaProblem.noSubscription.message, "no Go subscription")
        XCTAssertEqual(QuotaProblem.rateLimited.message, "rate limited")
        XCTAssertEqual(QuotaProblem.failed("Keychain access denied").message, "Keychain access denied")
    }

    // MARK: Schedule

    func testNeverFetchedIsDue() {
        XCTAssertTrue(QuotaSchedule.isDue(.tick, lastStarted: nil, rateLimitedUntil: nil, now: now))
        XCTAssertTrue(QuotaSchedule.isDue(.shown, lastStarted: nil, rateLimitedUntil: nil, now: now))
    }

    func testTheTickWaitsFiveMinutes() {
        XCTAssertFalse(QuotaSchedule.isDue(.tick, lastStarted: now.addingTimeInterval(-299), rateLimitedUntil: nil, now: now))
        XCTAssertTrue(QuotaSchedule.isDue(.tick, lastStarted: now.addingTimeInterval(-300), rateLimitedUntil: nil, now: now))
    }

    func testShowingTheWindowWaitsOneMinute() {
        XCTAssertFalse(QuotaSchedule.isDue(.shown, lastStarted: now.addingTimeInterval(-59), rateLimitedUntil: nil, now: now))
        XCTAssertTrue(QuotaSchedule.isDue(.shown, lastStarted: now.addingTimeInterval(-60), rateLimitedUntil: nil, now: now))
    }

    func testRateLimitedWaitsWhateverTheTrigger() {
        let until = now.addingTimeInterval(1)
        XCTAssertFalse(QuotaSchedule.isDue(.tick, lastStarted: nil, rateLimitedUntil: until, now: now))
        XCTAssertFalse(QuotaSchedule.isDue(.shown, lastStarted: nil, rateLimitedUntil: until, now: now))
        XCTAssertTrue(QuotaSchedule.isDue(.shown, lastStarted: nil, rateLimitedUntil: now, now: now))
    }

    func testRefreshingByHandIsDueAtOnce() {
        XCTAssertTrue(QuotaSchedule.isDue(.manual, lastStarted: now, rateLimitedUntil: nil, now: now))
    }

    /// Asking again while rate limited would only push the limit further out.
    func testRefreshingByHandStillWaitsOutARateLimit() {
        XCTAssertFalse(QuotaSchedule.isDue(.manual, lastStarted: nil,
                                           rateLimitedUntil: now.addingTimeInterval(1), now: now))
    }
}
