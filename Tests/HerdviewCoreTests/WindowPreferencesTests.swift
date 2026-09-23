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

    func testQuotaStartsCollapsed() {
        XCTAssertFalse(WindowPreferences(defaults: defaults).isQuotaExpanded)
    }

    func testExpandingTheQuotaSurvivesANewPreferencesObject() {
        WindowPreferences(defaults: defaults).isQuotaExpanded = true
        XCTAssertTrue(WindowPreferences(defaults: defaults).isQuotaExpanded)
    }

    func testTheOldCollapsedKeyNoLongerExpandsTheQuota() {
        defaults.set(false, forKey: "herdview.quotaCollapsed")
        XCTAssertFalse(WindowPreferences(defaults: defaults).isQuotaExpanded)

        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: "herdview.quotaCollapsed")
        XCTAssertFalse(WindowPreferences(defaults: defaults).isQuotaExpanded)
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
