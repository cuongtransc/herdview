import XCTest
@testable import HerdviewCore

/// Widest first, as FilterBar offers them: regular, small, small with short labels.
final class SegmentFitTests: XCTestCase {
    private let needs: [Double] = [420, 360, 300]

    func testWidestThatFitsWhenNothingIsShownYet() {
        XCTAssertEqual(SegmentFit.choose(available: 500, needs: needs, current: nil), 0)
        XCTAssertEqual(SegmentFit.choose(available: 420, needs: needs, current: nil), 0)
        XCTAssertEqual(SegmentFit.choose(available: 419, needs: needs, current: nil), 1)
        XCTAssertEqual(SegmentFit.choose(available: 300, needs: needs, current: nil), 2)
    }

    func testNothingFitsGivesTheNarrowest() {
        XCTAssertEqual(SegmentFit.choose(available: 100, needs: needs, current: nil), 2)
        XCTAssertEqual(SegmentFit.choose(available: 100, needs: needs, current: 0), 2)
    }

    /// Growing back needs room to spare, so a width on the edge — or a count
    /// that widens a label by a digit — cannot flip the choice every pass.
    func testGrowingBackNeedsSlack() {
        XCTAssertEqual(SegmentFit.choose(available: 425, needs: needs, current: 1), 1)
        XCTAssertEqual(SegmentFit.choose(available: 420 + SegmentFit.slack, needs: needs, current: 1), 0)
    }

    func testShrinksAsSoonAsTheCurrentNoLongerFits() {
        XCTAssertEqual(SegmentFit.choose(available: 419, needs: needs, current: 0), 1)
        XCTAssertEqual(SegmentFit.choose(available: 359, needs: needs, current: 1), 2)
    }

    /// The loop that crashed the app: the same width asked again and again,
    /// with the needs nudged each time, must settle on one answer.
    func testRepeatedAskingAtTheEdgeSettles() {
        var current: Int?
        var answers: [Int] = []
        for i in 0..<20 {
            let nudge = Double(i % 2) * 6
            current = SegmentFit.choose(available: 423, needs: [420 + nudge, 360, 300], current: current)
            answers.append(current!)
        }
        XCTAssertEqual(Set(answers.dropFirst(2)).count, 1, "\(answers)")
    }

    func testNoNeedsIsZero() {
        XCTAssertEqual(SegmentFit.choose(available: 400, needs: [], current: nil), 0)
    }
}
