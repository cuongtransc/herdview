import Foundation

public enum CmuxError: Error, Equatable, CustomStringConvertible {
    /// `cmux tree` answered with something this code cannot read.
    case unexpectedOutput

    public var description: String {
        switch self {
        case .unexpectedOutput: return "cmux tree: unexpected output"
        }
    }
}

/// One terminal tab in cmux. The tty is what ties it to a Herdr client.
public struct CmuxSurface: Equatable, Sendable {
    public let ref: String
    public let tty: String
    public let workspaceRef: String
    public let windowRef: String

    public init(ref: String, tty: String, workspaceRef: String, windowRef: String) {
        self.ref = ref
        self.tty = tty
        self.workspaceRef = workspaceRef
        self.windowRef = windowRef
    }
}

/// Every terminal tab cmux has open, and where the person is looking now.
public struct CmuxLayout: Equatable, Sendable {
    public let surfaces: [CmuxSurface]
    public let activeWindow: String?
    public let activeWorkspace: String?
    public let activePane: String?

    public init(surfaces: [CmuxSurface], activeWindow: String?, activeWorkspace: String?, activePane: String?) {
        self.surfaces = surfaces
        self.activeWindow = activeWindow
        self.activeWorkspace = activeWorkspace
        self.activePane = activePane
    }

    private struct Tree: Decodable {
        struct Active: Decodable {
            let windowRef: String?
            let workspaceRef: String?
            let paneRef: String?
            enum CodingKeys: String, CodingKey {
                case windowRef = "window_ref"
                case workspaceRef = "workspace_ref"
                case paneRef = "pane_ref"
            }
        }
        struct Window: Decodable { let ref: String; let workspaces: [Workspace]? }
        struct Workspace: Decodable { let ref: String; let panes: [Pane]? }
        struct Pane: Decodable { let surfaces: [Surface]? }
        struct Surface: Decodable { let ref: String; let tty: String? }

        let active: Active?
        let windows: [Window]
    }

    /// Parses `cmux tree --all --json`. Surfaces without a terminal (browser
    /// tabs and the like) are left out: nothing can be attached to them.
    public static func parse(tree data: Data) throws -> CmuxLayout {
        let tree: Tree
        do {
            tree = try JSONDecoder().decode(Tree.self, from: data)
        } catch {
            throw CmuxError.unexpectedOutput
        }
        var surfaces: [CmuxSurface] = []
        for window in tree.windows {
            for workspace in window.workspaces ?? [] {
                for pane in workspace.panes ?? [] {
                    for surface in pane.surfaces ?? [] {
                        guard let tty = surface.tty, !tty.isEmpty else { continue }
                        surfaces.append(CmuxSurface(ref: surface.ref, tty: tty,
                                                    workspaceRef: workspace.ref, windowRef: window.ref))
                    }
                }
            }
        }
        return CmuxLayout(surfaces: surfaces, activeWindow: tree.active?.windowRef,
                          activeWorkspace: tree.active?.workspaceRef, activePane: tree.active?.paneRef)
    }
}
