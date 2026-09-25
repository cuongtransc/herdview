import Foundation

/// The cmux calls a Jump makes, as argv for `ProcessRunner`.
public enum CmuxCommand {
    public static func tree(cmux: String) -> HostCommand {
        HostCommand(executable: cmux, arguments: ["tree", "--all", "--json"])
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
        var arguments = ["new-surface", "--type", "terminal", "--focus", "true", "--command", command]
        for (flag, ref) in [("--window", layout.activeWindow),
                            ("--workspace", layout.activeWorkspace),
                            ("--pane", layout.activePane)] {
            if let ref { arguments += [flag, ref] }
        }
        return HostCommand(executable: cmux, arguments: arguments)
    }

    /// What a failed cmux call says to the person: its last stderr line, or
    /// how to fix the one refusal every Dock-launched Herdview meets — cmux's
    /// default socket mode admits only processes started inside cmux.
    public static func failure(stderr: String, exitCode: Int32) -> String {
        if stderr.contains("only processes started inside cmux") {
            return "cmux only lets in apps started inside it — set Settings › Automation to Password, or run `mise run cmux:setup`"
        }
        let last = stderr.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        return last ?? "exit \(exitCode)"
    }
}
