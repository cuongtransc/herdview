import XCTest
@testable import HerdviewCore

final class WindowPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "herdview.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testAlwaysOnTopIsOffUntilTheUserAsksForIt() {
        let prefs = WindowPreferences(defaults: defaults)
        XCTAssertFalse(prefs.isAlwaysOnTop)
    }

    func testAlwaysOnTopSurvivesANewPreferencesObject() {
        WindowPreferences(defaults: defaults).isAlwaysOnTop = true
        XCTAssertTrue(WindowPreferences(defaults: defaults).isAlwaysOnTop)
    }

    func testTurningAlwaysOnTopBackOffSticks() {
        let prefs = WindowPreferences(defaults: defaults)
        prefs.isAlwaysOnTop = true
        prefs.isAlwaysOnTop = false
        XCTAssertFalse(WindowPreferences(defaults: defaults).isAlwaysOnTop)
    }

    func testQuotaCardIsExpandedUntilTheUserCollapsesIt() {
        XCTAssertFalse(WindowPreferences(defaults: defaults).isQuotaCollapsed)
    }

    func testCollapsingTheQuotaCardSurvivesANewPreferencesObject() {
        WindowPreferences(defaults: defaults).isQuotaCollapsed = true
        XCTAssertTrue(WindowPreferences(defaults: defaults).isQuotaCollapsed)
    }

    func testAgentScopeDefaultsToAll() {
        XCTAssertEqual(WindowPreferences(defaults: defaults).agentScope, .all)
    }

    func testChoosingAStatusScopeSurvivesANewPreferencesObject() {
        WindowPreferences(defaults: defaults).agentScope = .needsMe
        XCTAssertEqual(WindowPreferences(defaults: defaults).agentScope, .needsMe)
    }

    func testAnUnknownStoredScopeReadsBackAsAll() {
        defaults.set("bogus", forKey: "herdview.agentScope")
        XCTAssertEqual(WindowPreferences(defaults: defaults).agentScope, .all)
    }
}
