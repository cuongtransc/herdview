import Foundation

/// A terminal attached to a Herdr Session, read from one line of `ps`.
///
/// Herdr has no API that lists its clients, but every attached client is a
/// process on a terminal whose argv names the Session: a local `herdr`, an
/// `ssh` running `herdr session attach` on a remote Host, or `herdr --remote`.
/// The terminal is what cmux knows a tab by, so this is how a Session is
/// matched to the tab showing it.
public struct AttachClient: Equatable, Sendable {
    public let tty: String
    /// The ssh target exactly as typed on the command line; nil for a client
    /// of a Session on this Mac.
    public let sshTarget: String?
    public let session: String

    public init(tty: String, sshTarget: String?, session: String) {
        self.tty = tty
        self.sshTarget = sshTarget
        self.session = session
    }

    static let defaultSession = "default"
    /// The ssh(1) options that take a value.
    private static let sshValueFlags = Set("BbcDEeFIiJLlmOoPpQRSWw")

    /// Parses `ps -axo pid=,tty=,command=`. Lines with no terminal, and every
    /// process that is not a client, are skipped. `ps` has already lost any
    /// quoting, so a Session name with a space is never recognised.
    public static func parse(ps: String) -> [AttachClient] {
        var clients: [AttachClient] = []
        for line in ps.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard fields.count >= 3, Int(fields[0]) != nil else { continue }
            let tty = fields[1]
            guard tty != "??", tty != "?" else { continue }
            let argv = Array(fields[2...])
            let rest = Array(argv.dropFirst())
            let client: AttachClient?
            switch basename(argv[0]) {
            case "herdr": client = herdrClient(tty: tty, rest: rest)
            case "ssh": client = sshClient(tty: tty, rest: rest)
            default: client = nil
            }
            if let client { clients.append(client) }
        }
        return clients
    }

    private static func basename(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// `herdr`, `herdr --session S`, `herdr session attach S`, or
    /// `herdr --remote T [--session S]`. Anything else — the server, API calls,
    /// `--machine` — is not a client of a Session this app watches.
    private static func herdrClient(tty: String, rest: [String]) -> AttachClient? {
        var rest = rest
        guard !rest.contains("--machine") else { return nil }
        var session = defaultSession
        if let i = rest.firstIndex(of: "--session") {
            guard i + 1 < rest.count else { return nil }
            session = rest[i + 1]
            rest.removeSubrange(i...(i + 1))
        }
        var target: String?
        if let i = rest.firstIndex(of: "--remote") {
            guard i + 1 < rest.count else { return nil }
            target = rest[i + 1]
            rest.removeSubrange(i...(i + 1))
        }
        if rest.isEmpty {
            return AttachClient(tty: tty, sshTarget: target, session: session)
        }
        if target == nil, rest.count == 3, rest[0] == "session", rest[1] == "attach" {
            return AttachClient(tty: tty, sshTarget: nil, session: rest[2])
        }
        return nil
    }

    /// `ssh [options] T <path>/herdr session attach S`. The target is the first
    /// word that is not an option or an option's value.
    private static func sshClient(tty: String, rest: [String]) -> AttachClient? {
        var i = 0
        while i < rest.count, rest[i].hasPrefix("-") {
            let word = rest[i]
            i += 1
            if word == "--" { break }
            // `-tp 22` and `-p22` both carry a value; only the first takes the
            // next word for it.
            let flags = Array(word.dropFirst())
            if let at = flags.firstIndex(where: { sshValueFlags.contains($0) }), at == flags.count - 1 {
                i += 1
            }
        }
        guard i < rest.count else { return nil }
        let target = rest[i]
        let command = Array(rest[(i + 1)...])
        guard command.count == 4, basename(command[0]) == "herdr",
              command[1] == "session", command[2] == "attach" else { return nil }
        return AttachClient(tty: tty, sshTarget: target, session: command[3])
    }
}
