import Foundation

/// One machine running Herdr. `ssh == nil` means the local machine.
public struct HostConfig: Equatable, Sendable {
    public var name: String
    public var ssh: String?
    public var herdrPath: String
    public var pollSeconds: Int

    public init(name: String, ssh: String?, herdrPath: String, pollSeconds: Int) {
        self.name = name
        self.ssh = ssh
        self.herdrPath = herdrPath
        self.pollSeconds = pollSeconds
    }

    public var isLocal: Bool { ssh == nil }
}

public struct HerdviewConfig: Equatable, Sendable {
    public var hosts: [HostConfig]
    /// Providers the Quota card leaves out, from `hidden_providers`. A Provider
    /// with no account on this Mac is a row that can only ever say "not signed
    /// in", which in a card of numbers is noise.
    public var hiddenProviders: Set<QuotaProvider>
    /// Where `cmux` is, from `cmux_path`; nil means look in the usual places.
    public var cmuxPath: String?

    public init(hosts: [HostConfig], hiddenProviders: Set<QuotaProvider> = [], cmuxPath: String? = nil) {
        self.hosts = hosts
        self.hiddenProviders = hiddenProviders
        self.cmuxPath = cmuxPath
    }

    /// What the Quota card shows and what is fetched for it: every Provider in
    /// `QuotaProvider.allCases` order except the hidden ones, so hiding one
    /// never moves the rows that are left.
    public var watchedProviders: [QuotaProvider] {
        QuotaProvider.allCases.filter { !hiddenProviders.contains($0) }
    }
}

public enum ConfigError: Error, Equatable {
    case parse(String)
    case missingField(host: Int, field: String)
    case invalidType(String)
    case unknownProvider(String)
}

public enum ConfigLoader {
    public static let defaultPath = NSHomeDirectory() + "/.config/herdview/config.toml"
    public static let defaultPollSeconds = 2
    /// What a config written on a first run calls this Mac.
    public static let defaultLocalHostName = "local"

    /// What `loadOrCreate` did to the file, so the caller can say it in the log
    /// instead of in the window.
    public enum Origin: Equatable, Sendable {
        /// The config was already on disk.
        case existing
        /// A first-run config was written.
        case created
        /// Nothing was on disk and nothing could be written, so the built-in
        /// default is in use for this launch only.
        case inMemory
    }

    public struct Load: Equatable, Sendable {
        public let config: HerdviewConfig
        public let origin: Origin

        public init(config: HerdviewConfig, origin: Origin) {
            self.config = config
            self.origin = origin
        }
    }

    public static func load(path: String = defaultPath) throws -> HerdviewConfig {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            throw ConfigError.parse("cannot read \(path)")
        }
        return try parse(text)
    }

    /// Loads `path`, writing a first-run config there when nothing exists yet.
    ///
    /// A missing file is a first run, not an error: the app has nothing to watch
    /// until it is told what to watch, and being told to go and edit a file that
    /// does not exist is a worse first launch than one already showing this Mac.
    /// A file that is there but cannot be read or parsed still throws — that is
    /// worth saying, and rewriting it would throw the user's own edits away.
    public static func loadOrCreate(path: String = defaultPath,
                                    herdrPath: String = findHerdr()) throws -> Load {
        if FileManager.default.fileExists(atPath: path) {
            return Load(config: try load(path: path), origin: .existing)
        }

        let config = HerdviewConfig(hosts: [
            HostConfig(name: defaultLocalHostName, ssh: nil,
                       herdrPath: herdrPath, pollSeconds: defaultPollSeconds),
        ])
        let text = defaultConfigText(herdrPath: herdrPath)
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let wrote = (try? Data(text.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)) != nil
        return Load(config: config, origin: wrote ? .created : .inMemory)
    }

    /// The file written on a first run: this Mac, already watched, so the window
    /// has something to show before anyone has read the README. A remote host is
    /// commented out rather than left out — the shape is the documentation.
    public static func defaultConfigText(herdrPath: String) -> String {
        """
        # Herdview — the machines running Herdr that the window watches.
        #
        # Providers the Quota card should leave out, so a row you have no
        # account for is not a row that can only say "not signed in". Any of:
        # claude, codex, opencodeGo, grok. Keep this above the first [[hosts]].
        # hidden_providers = ["codex"]
        #
        # A host with no `ssh` is this Mac. `herdr_path` must be absolute: a GUI
        # app is not started by a login shell, so it inherits none of your PATH,
        # and `~` is not expanded. `poll_seconds` is optional.
        #
        # [[hosts]]
        # name = "devtuf"                    # the name the window groups by
        # ssh = "devtuf"                     # ssh alias, or user@host
        # herdr_path = "/home/you/.local/bin/herdr"
        # poll_seconds = 2                   # default 2

        [[hosts]]
        name = "\(defaultLocalHostName)"
        herdr_path = "\(herdrPath)"
        """
    }

    /// Where `herdr` is on this Mac, for the config written on a first run.
    ///
    /// PATH alone is not enough to go on: Finder hands a GUI app
    /// `/usr/bin:/bin:/usr/sbin:/sbin`, so the places Homebrew and the
    /// installer's per-user prefix put it are checked first and PATH last. When
    /// none of them exists the Homebrew path is written anyway — the file is
    /// meant to be edited, and a plausible path is a better place to start than
    /// an empty one.
    public static func findHerdr(
        home: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String {
        let usual = ["/opt/homebrew/bin/herdr", "/usr/local/bin/herdr", home + "/.local/bin/herdr"]
        // An empty PATH entry means the working directory to a shell, which is
        // never where herdr is installed; skip it rather than look for `/herdr`.
        let fromPath = (environment["PATH"] ?? "")
            .split(separator: ":")
            .filter { !$0.isEmpty }
            .map { "\($0)/herdr" }
        return (usual + fromPath).first(where: isExecutable) ?? usual[0]
    }

    /// Where `cmux` is on this Mac, for a Jump. Unlike `findHerdr` there is no
    /// fallback: with no cmux a Jump says so instead of running a path that is
    /// not there.
    public static func findCmux(
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        ["/opt/homebrew/bin/cmux", "/usr/local/bin/cmux", "/Applications/cmux.app/Contents/Resources/bin/cmux"]
            .first(where: isExecutable)
    }

    public static func parse(_ text: String) throws -> HerdviewConfig {
        let doc: TOMLDocument
        do {
            doc = try TOMLSubset.parse(text)
        } catch let TOMLSubsetError.syntax(line, message) {
            throw ConfigError.parse("line \(line): \(message)")
        }

        // `pet`, `[clips]` and `[messages]` are no longer read. They parse as
        // ordinary TOML and are ignored, so a config written for the pet still
        // loads; the README says they are gone.
        var hidden: Set<QuotaProvider> = []
        if let raw = doc.root["hidden_providers"] {
            guard case .array(let items) = raw else {
                throw ConfigError.invalidType("hidden_providers must be an array of Provider names")
            }
            for (index, item) in items.enumerated() {
                guard let name = item.stringValue else {
                    throw ConfigError.invalidType("hidden_providers[\(index)] must be a string")
                }
                guard let provider = QuotaProvider(name: name) else {
                    throw ConfigError.unknownProvider(name)
                }
                hidden.insert(provider)
            }
        }

        var cmuxPath: String?
        if let raw = doc.root["cmux_path"] {
            guard let value = raw.stringValue else { throw ConfigError.invalidType("cmux_path must be a string") }
            cmuxPath = value
        }

        var hosts: [HostConfig] = []
        for (index, entry) in (doc.arrays["hosts"] ?? []).enumerated() {
            guard let name = entry["name"]?.stringValue else { throw ConfigError.missingField(host: index, field: "name") }
            guard let herdrPath = entry["herdr_path"]?.stringValue else { throw ConfigError.missingField(host: index, field: "herdr_path") }
            let ssh = entry["ssh"]?.stringValue
            var poll = defaultPollSeconds
            if let raw = entry["poll_seconds"] {
                guard let value = raw.intValue, value >= 1 else { throw ConfigError.invalidType("hosts[\(index)].poll_seconds must be an integer >= 1") }
                poll = value
            }
            hosts.append(HostConfig(name: name, ssh: ssh, herdrPath: herdrPath, pollSeconds: poll))
        }

        return HerdviewConfig(hosts: hosts, hiddenProviders: hidden, cmuxPath: cmuxPath)
    }
}
