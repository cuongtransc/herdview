import Foundation

/// A command to run for a host: directly for local, wrapped in ssh for remote.
public struct HostCommand: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    public static func sessionList(for host: HostConfig) -> HostCommand {
        if let ssh = host.ssh {
            return HostCommand(
                executable: "/usr/bin/ssh",
                arguments: ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", ssh, "\(host.herdrPath) session list --json"])
        }
        return HostCommand(executable: host.herdrPath, arguments: ["session", "list", "--json"])
    }

    /// What a new terminal tab runs to show `session`. Remote Hosts go through
    /// `ssh -t`, so the tab gets a real terminal on the remote end; the remote
    /// command is one word, quoted for the remote shell that ssh hands it to.
    public static func attach(for host: HostConfig, session: String) -> HostCommand {
        if let ssh = host.ssh {
            let remote = [host.herdrPath, "session", "attach", session].map(shellQuote).joined(separator: " ")
            return HostCommand(executable: "/usr/bin/ssh", arguments: ["-t", ssh, remote])
        }
        return HostCommand(executable: host.herdrPath, arguments: ["session", "attach", session])
    }

    /// This command as one line for a shell, each word quoted only when it has
    /// to be — cmux runs `--command` through one.
    public var shellLine: String {
        ([executable] + arguments).map(Self.shellQuote).joined(separator: " ")
    }

    private static let shellSafe = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%+=:,./-_")

    static func shellQuote(_ word: String) -> String {
        if !word.isEmpty, word.unicodeScalars.allSatisfy(shellSafe.contains) { return word }
        return "'" + word.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
