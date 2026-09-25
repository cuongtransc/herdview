import Foundation
import XCTest
@testable import HerdviewCore

final class ConfigLoaderTests: XCTestCase {
    func testFullSample() throws {
        let text = """
        pet = "boba"

        [clips]
        blocked = 3

        [[hosts]]
        name = "local"
        herdr_path = "/opt/homebrew/bin/herdr"

        [[hosts]]
        name = "devtuf"
        ssh = "devtuf"
        herdr_path = "/home/cuongnb/.local/bin/herdr"
        poll_seconds = 5
        """
        let config = try ConfigLoader.parse(text)
        XCTAssertEqual(config.hosts.count, 2)
        XCTAssertEqual(config.hosts[0], HostConfig(name: "local", ssh: nil, herdrPath: "/opt/homebrew/bin/herdr", pollSeconds: 2))
        XCTAssertTrue(config.hosts[0].isLocal)
        XCTAssertEqual(config.hosts[1], HostConfig(name: "devtuf", ssh: "devtuf", herdrPath: "/home/cuongnb/.local/bin/herdr", pollSeconds: 5))
        XCTAssertFalse(config.hosts[1].isLocal)
    }

    func testDefaultsWhenOptionalFieldsAbsent() throws {
        let config = try ConfigLoader.parse("""
        [[hosts]]
        name = "local"
        herdr_path = "/opt/homebrew/bin/herdr"
        """)
        XCTAssertEqual(config.hosts[0].pollSeconds, 2)
    }

    func testMissingHerdrPathThrows() {
        XCTAssertThrowsError(try ConfigLoader.parse("[[hosts]]\nname = \"local\"")) { error in
            XCTAssertEqual(error as? ConfigError, .missingField(host: 0, field: "herdr_path"))
        }
    }

    func testMissingNameThrows() {
        XCTAssertThrowsError(try ConfigLoader.parse("[[hosts]]\nherdr_path = \"/x\"")) { error in
            XCTAssertEqual(error as? ConfigError, .missingField(host: 0, field: "name"))
        }
    }

    func testNoHostsIsValidButEmpty() throws {
        let config = try ConfigLoader.parse("pet = \"boba\"")
        XCTAssertTrue(config.hosts.isEmpty)
    }

    func testLoadMissingFileThrowsParse() {
        XCTAssertThrowsError(try ConfigLoader.load(path: "/nonexistent/herdview.toml")) { error in
            guard case ConfigError.parse? = error as? ConfigError else { return XCTFail("expected parse error, got \(error)") }
        }
    }

    // MARK: - First run

    /// A path under a directory that does not exist yet, so the write also has
    /// to make the directory the way a real first run does.
    private func temporaryConfigPath() -> String {
        NSTemporaryDirectory() + "herdview-config-\(UUID().uuidString)/herdview/config.toml"
    }

    private func removeConfigTree(at path: String) {
        // Two levels up: `<tmp>/<case>/herdview/config.toml`, and the case's
        // own directory is ours to take away with it.
        let tree = ((path as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        try? FileManager.default.removeItem(atPath: tree)
    }

    func testFirstRunWritesAConfigAndReturnsTheSameOne() throws {
        let path = temporaryConfigPath()
        defer { removeConfigTree(at: path) }

        let load = try ConfigLoader.loadOrCreate(path: path, herdrPath: "/opt/homebrew/bin/herdr")

        XCTAssertEqual(load.origin, .created)
        XCTAssertEqual(load.config.hosts, [HostConfig(name: "local", ssh: nil,
                                                      herdrPath: "/opt/homebrew/bin/herdr",
                                                      pollSeconds: ConfigLoader.defaultPollSeconds)])
        XCTAssertTrue(load.config.hosts[0].isLocal)
        // The file it wrote is the config it handed back: a second run reads
        // that file instead of writing again, whatever it is told about herdr.
        XCTAssertEqual(try ConfigLoader.load(path: path), load.config)
        let second = try ConfigLoader.loadOrCreate(path: path, herdrPath: "/nonexistent/herdr")
        XCTAssertEqual(second, ConfigLoader.Load(config: load.config, origin: .existing))
    }

    func testAnExistingConfigIsNeverRewritten() throws {
        let path = temporaryConfigPath()
        defer { removeConfigTree(at: path) }
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        let mine = "[[hosts]]\nname = \"devtuf\"\nssh = \"devtuf\"\nherdr_path = \"/usr/bin/herdr\"\n"
        try Data(mine.utf8).write(to: URL(fileURLWithPath: path))

        let load = try ConfigLoader.loadOrCreate(path: path, herdrPath: "/opt/homebrew/bin/herdr")

        XCTAssertEqual(load.origin, .existing)
        XCTAssertEqual(load.config.hosts.map(\.name), ["devtuf"])
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), mine)
    }

    func testAMalformedConfigStillThrowsRatherThanBeingOverwritten() throws {
        let path = temporaryConfigPath()
        defer { removeConfigTree(at: path) }
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try Data("[[hosts]]\nname = \"local\"\n".utf8).write(to: URL(fileURLWithPath: path))

        XCTAssertThrowsError(try ConfigLoader.loadOrCreate(path: path)) { error in
            XCTAssertEqual(error as? ConfigError, .missingField(host: 0, field: "herdr_path"))
        }
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "[[hosts]]\nname = \"local\"\n")
    }

    func testDefaultConfigTextNamesTheHostItWasGiven() throws {
        let text = ConfigLoader.defaultConfigText(herdrPath: "/Users/me/.local/bin/herdr")
        XCTAssertEqual(try ConfigLoader.parse(text).hosts,
                       [HostConfig(name: "local", ssh: nil,
                                   herdrPath: "/Users/me/.local/bin/herdr",
                                   pollSeconds: ConfigLoader.defaultPollSeconds)])
    }

    // MARK: - Hidden Providers

    func testHiddenProvidersLeavesTheRowsThatAreLeftWhereTheyWere() throws {
        let config = try ConfigLoader.parse("""
        hidden_providers = ["codex"]

        [[hosts]]
        name = "local"
        herdr_path = "/opt/homebrew/bin/herdr"
        """)
        XCTAssertEqual(config.hiddenProviders, [.codex])
        XCTAssertEqual(config.watchedProviders, [.claude, .opencodeGo, .grok])
    }

    func testWithNothingHiddenEveryProviderIsWatched() throws {
        let config = try ConfigLoader.parse("[[hosts]]\nname = \"local\"\nherdr_path = \"/x\"\n")
        XCTAssertTrue(config.hiddenProviders.isEmpty)
        XCTAssertEqual(config.watchedProviders, QuotaProvider.allCases)
    }

    func testHiddenProvidersAcceptsAnySpellingOfAName() throws {
        let config = try ConfigLoader.parse("""
        hidden_providers = ["OpenCode Go", "opencode_go", "opencode-go"]
        """)
        XCTAssertEqual(config.hiddenProviders, [.opencodeGo])
    }

    func testHidingEveryProviderIsAllowedAndShowsNothing() throws {
        let config = try ConfigLoader.parse("""
        hidden_providers = ["claude", "codex", "opencodeGo", "grok"]
        """)
        XCTAssertEqual(config.watchedProviders, [])
    }

    func testAnUnknownProviderNameThrows() {
        XCTAssertThrowsError(try ConfigLoader.parse("hidden_providers = [\"gpt5\"]\n")) { error in
            XCTAssertEqual(error as? ConfigError, .unknownProvider("gpt5"))
        }
    }

    func testHiddenProvidersMustBeAnArrayOfStrings() {
        XCTAssertThrowsError(try ConfigLoader.parse("hidden_providers = \"codex\"\n")) { error in
            guard case ConfigError.invalidType? = error as? ConfigError else {
                return XCTFail("expected invalidType, got \(error)")
            }
        }
        XCTAssertThrowsError(try ConfigLoader.parse("hidden_providers = [3]\n")) { error in
            XCTAssertEqual(error as? ConfigError, .invalidType("hidden_providers[0] must be a string"))
        }
    }

    // MARK: - Finding herdr

    func testFindHerdrChecksTheUsualPlacesBeforePath() {
        // Both a usual place and PATH offer herdr; the usual one wins, so a
        // Finder launch with `/usr/bin:/bin` still finds Homebrew's.
        let usualWins = ConfigLoader.findHerdr(
            home: "/Users/me",
            environment: ["PATH": "/nix/store/bin"],
            isExecutable: { $0 == "/opt/homebrew/bin/herdr" || $0 == "/nix/store/bin/herdr" })
        XCTAssertEqual(usualWins, "/opt/homebrew/bin/herdr")

        // And the usual places have an order of their own: Apple Silicon
        // Homebrew, then the Intel prefix, then the installer's per-user one.
        let firstUsual = ConfigLoader.findHerdr(
            home: "/Users/me",
            environment: [:],
            isExecutable: { $0 == "/usr/local/bin/herdr" || $0 == "/Users/me/.local/bin/herdr" })
        XCTAssertEqual(firstUsual, "/usr/local/bin/herdr")
    }

    func testFindHerdrSearchesPathWhenNothingUsualIsInstalled() {
        let found = ConfigLoader.findHerdr(
            home: "/Users/me",
            environment: ["PATH": "/nix/store/bin::/usr/bin"],
            isExecutable: { $0 == "/nix/store/bin/herdr" })
        XCTAssertEqual(found, "/nix/store/bin/herdr")
    }

    func testFindHerdrFallsBackToTheHomebrewPathItWouldHaveFound() {
        let found = ConfigLoader.findHerdr(home: "/Users/me", environment: [:],
                                          isExecutable: { _ in false })
        XCTAssertEqual(found, "/opt/homebrew/bin/herdr")
    }

    func testCmuxPathIsRead() throws {
        let config = try ConfigLoader.parse("""
        cmux_path = "/opt/cmux/bin/cmux"

        [[hosts]]
        name = "local"
        herdr_path = "/opt/homebrew/bin/herdr"
        """)
        XCTAssertEqual(config.cmuxPath, "/opt/cmux/bin/cmux")
    }

    func testCmuxPathDefaultsToNil() throws {
        XCTAssertNil(try ConfigLoader.parse("").cmuxPath)
    }

    func testCmuxPathMustBeAString() {
        XCTAssertThrowsError(try ConfigLoader.parse("cmux_path = 3\n")) { error in
            XCTAssertEqual(error as? ConfigError, .invalidType("cmux_path must be a string"))
        }
    }

    func testFindCmuxTakesTheFirstExecutable() {
        XCTAssertEqual(ConfigLoader.findCmux(isExecutable: { $0 == "/Applications/cmux.app/Contents/Resources/bin/cmux" }),
                       "/Applications/cmux.app/Contents/Resources/bin/cmux")
        XCTAssertEqual(ConfigLoader.findCmux(isExecutable: { _ in true }), "/opt/homebrew/bin/cmux")
        XCTAssertNil(ConfigLoader.findCmux(isExecutable: { _ in false }))
    }
}
