import XCTest
@testable import HerdviewCore

final class JumpTabsTests: XCTestCase {
    private var path: String!

    override func setUpWithError() throws {
        path = FileManager.default.temporaryDirectory
            .appendingPathComponent("jump-tabs-\(UUID().uuidString)/tabs.json").path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }

    func testRememberedTabSurvivesAReload() throws {
        var tabs = JumpTabs(path: path)
        tabs.remember("F35E", host: "hms", session: "default")
        tabs.remember("AAAA", host: "local", session: "work")
        try tabs.save()

        let reloaded = JumpTabs.load(path: path)
        XCTAssertEqual(reloaded.surface(host: "hms", session: "default"), "F35E")
        XCTAssertEqual(reloaded.surface(host: "local", session: "work"), "AAAA")
        XCTAssertNil(reloaded.surface(host: "hms", session: "work"))
    }

    func testRememberReplacesAndForgetDrops() {
        var tabs = JumpTabs(path: path)
        tabs.remember("OLD", host: "hms", session: "default")
        tabs.remember("NEW", host: "hms", session: "default")
        XCTAssertEqual(tabs.surface(host: "hms", session: "default"), "NEW")
        tabs.forget(host: "hms", session: "default")
        XCTAssertNil(tabs.surface(host: "hms", session: "default"))
    }

    func testMissingOrUnreadableFileLoadsEmpty() throws {
        XCTAssertNil(JumpTabs.load(path: path).surface(host: "hms", session: "default"))
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: URL(fileURLWithPath: path))
        XCTAssertNil(JumpTabs.load(path: path).surface(host: "hms", session: "default"))
    }
}
