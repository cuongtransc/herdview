import Foundation

/// The cmux tab Herdview last opened for each Session, by surface id, kept in
/// `~/.herdview/jump-tabs.json` so a relaunch still finds it. cmux reports no
/// tty for a tab it opens, so without this every Jump to that Session would
/// open another tab.
public struct JumpTabs: Sendable {
    public static let defaultPath = NSHomeDirectory() + "/.herdview/jump-tabs.json"

    public let path: String
    private var surfaces: [String: String]

    public init(path: String = defaultPath) {
        self.path = path
        self.surfaces = [:]
    }

    /// What `path` holds; empty when it is missing or unreadable, since a lost
    /// memory only costs one extra tab.
    public static func load(path: String = defaultPath) -> JumpTabs {
        var tabs = JumpTabs(path: path)
        if let data = FileManager.default.contents(atPath: path),
           let surfaces = try? JSONDecoder().decode([String: String].self, from: data) {
            tabs.surfaces = surfaces
        }
        return tabs
    }

    public func surface(host: String, session: String) -> String? {
        surfaces[Self.key(host, session)]
    }

    public mutating func remember(_ surface: String, host: String, session: String) {
        surfaces[Self.key(host, session)] = surface
    }

    public mutating func forget(host: String, session: String) {
        surfaces[Self.key(host, session)] = nil
    }

    public func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try encoder.encode(surfaces).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private static func key(_ host: String, _ session: String) -> String { "\(host)/\(session)" }
}
