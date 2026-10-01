import XCTest
@testable import HerdviewCore

final class SavedWindowFrameTests: XCTestCase {
    /// What macOS saved on 2026-10-01 after a drag into the top edge filled the window.
    private let filled = #"-1701 1117 2560 1410 -1701 1117 2560 1410 {"tilingState":{"tilingPosition":9,"normalizedSize":1,"untiledFrame":"{{514, -1410}, {466, 1410}}"}}"#

    /// The size from before the tile, centred on the screen the window was on.
    func testAFilledFrameComesBackAtItsUntiledSize() {
        XCTAssertEqual(SavedWindowFrame.untiled(filled), "-654 1117 466 1410 -1701 1117 2560 1410")
    }

    func testAnUntiledFrameIsLeftAlone() {
        XCTAssertNil(SavedWindowFrame.untiled("390 1388 468 1005 -1701 1117 2560 1410"))
    }

    func testAnUntiledSizeLargerThanTheScreenIsClamped() {
        let saved = #"0 0 1728 1084 0 0 1728 1084 {"tilingState":{"untiledFrame":"{{0, 0}, {2000, 1200}}"}}"#
        XCTAssertEqual(SavedWindowFrame.untiled(saved), "0 0 1728 1084 0 0 1728 1084")
    }

    /// Without a size to go back to there is nothing better to write.
    func testATiledFrameWithoutAnUntiledSizeIsLeftAlone() {
        XCTAssertNil(SavedWindowFrame.untiled(#"0 0 1728 1084 0 0 1728 1084 {"tilingState":{"tilingPosition":9}}"#))
        XCTAssertNil(SavedWindowFrame.untiled(#"0 0 {"tilingState":{"untiledFrame":"{{0, 0}, {400, 400}}"}}"#))
    }
}
