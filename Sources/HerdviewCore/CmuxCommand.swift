import Foundation

/// The cmux calls a Jump makes, as argv for `ProcessRunner`.
public enum CmuxCommand {
    public static func tree(cmux: String) -> HostCommand {
        HostCommand(executable: cmux, arguments: ["tree", "--all", "--json", "--id-format", "both"])
    }

    /// Brings a tab forward; cmux switches workspace and window with it.
    public static func focus(cmux: String, surface: CmuxSurface) -> HostCommand {
        HostCommand(executable: cmux, arguments: [
            "focus-panel", "--panel", surface.ref,
            "--workspace", surface.workspaceRef,
            "--window", surface.windowRef,
        ])
    }

    /// Opens a focused terminal tab running `command`, beside the tab the
    /// person is looking at when cmux says which one that is.
    public static func open(cmux: String, layout: CmuxLayout, command: String) -> HostCommand {
        // uuids: the new tab's id comes back first, for `openedSurfaceId`.
        var arguments = ["new-surface", "--type", "terminal", "--focus", "true", "--command", command,
                         "--id-format", "uuids"]
        for (flag, ref) in [("--window", layout.activeWindow),
                            ("--workspace", layout.activeWorkspace),
                            ("--pane", layout.activePane)] {
            if let ref { arguments += [flag, ref] }
        }
        return HostCommand(executable: cmux, arguments: arguments)
    }

    /// The id of the tab `open` made, from its `OK <surface> <pane> <workspace>`.
    public static func openedSurfaceId(output: String) -> String? {
        let words = output.split(whereSeparator: \.isWhitespace)
        guard words.count >= 2, words[0] == "OK" else { return nil }
        return String(words[1])
    }

    /// What a failed cmux call says to the person: its last stderr line, or
    /// how to fix the one refusal every Dock-launched Herdview meets — cmux's
    /// default socket mode admits only processes started inside cmux.
    public static func failure(stderr: String, exitCode: Int32) -> String {
        if stderr.contains("only processes started inside cmux") {
            return "cmux only lets in apps started inside it — set Settings › Automation › Socket Control Mode to Automation mode, or run `mise run cmux:setup`"
        }
        let last = stderr.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        return last ?? "exit \(exitCode)"
    }
}
