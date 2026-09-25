import XCTest
@testable import HerdviewCore

/// The shape is `cmux tree --all --json` as cmux printed it on 2026-09-25,
/// cut down to the keys Herdview reads plus a few it must ignore.
final class CmuxLayoutTests: XCTestCase {
    private let tree = """
    {"active":{"pane_ref":"pane:15","surface_ref":"surface:190","window_ref":"window:2","workspace_ref":"workspace:14","is_browser_surface":false},
     "caller":null,
     "windows":[
      {"ref":"window:1","index":0,"workspaces":[
        {"ref":"workspace:3","title":"a","panes":[
          {"ref":"pane:7","surfaces":[
            {"ref":"surface:216","tty":"ttys016","type":"terminal","title":"htop","pane_ref":"pane:7"},
            {"ref":"surface:217","tty":null,"type":"browser","url":"https://x"}
          ]}
        ]}
      ]},
      {"ref":"window:2","workspaces":[
        {"ref":"workspace:14","panes":[
          {"ref":"pane:15","surfaces":[{"ref":"surface:190","tty":"ttys020","type":"terminal"}]},
          {"ref":"pane:16"}
        ]},
        {"ref":"workspace:15"}
      ]}
     ]}
    """

    func testParseKeepsTerminalSurfacesAndActiveRefs() throws {
        let layout = try CmuxLayout.parse(tree: Data(tree.utf8))
        XCTAssertEqual(layout, CmuxLayout(
            surfaces: [
                CmuxSurface(ref: "surface:216", tty: "ttys016", workspaceRef: "workspace:3", windowRef: "window:1"),
                CmuxSurface(ref: "surface:190", tty: "ttys020", workspaceRef: "workspace:14", windowRef: "window:2"),
            ],
            activeWindow: "window:2", activeWorkspace: "workspace:14", activePane: "pane:15"))
    }

    func testNoActiveBlockIsFine() throws {
        let layout = try CmuxLayout.parse(tree: Data(#"{"windows":[]}"#.utf8))
        XCTAssertEqual(layout, CmuxLayout(surfaces: [], activeWindow: nil, activeWorkspace: nil, activePane: nil))
    }

    func testMalformedTreeThrows() {
        for text in ["", "not json", #"{"active":{}}"#, #"{"windows":[{"workspaces":[]}]}"#] {
            XCTAssertThrowsError(try CmuxLayout.parse(tree: Data(text.utf8)), text) { error in
                XCTAssertEqual(error as? CmuxError, .unexpectedOutput)
            }
        }
    }

    func testCommands() {
        let surface = CmuxSurface(ref: "surface:190", tty: "ttys020", workspaceRef: "workspace:14", windowRef: "window:2")
        XCTAssertEqual(CmuxCommand.tree(cmux: "/c"),
                       HostCommand(executable: "/c", arguments: ["tree", "--all", "--json", "--id-format", "both"]))
        XCTAssertEqual(CmuxCommand.focus(cmux: "/c", surface: surface),
                       HostCommand(executable: "/c", arguments: [
                           "focus-panel", "--panel", "surface:190", "--workspace", "workspace:14", "--window", "window:2"]))
        let full = CmuxLayout(surfaces: [], activeWindow: "window:2", activeWorkspace: "workspace:14", activePane: "pane:15")
        XCTAssertEqual(CmuxCommand.open(cmux: "/c", layout: full, command: "herdr session attach x"),
                       HostCommand(executable: "/c", arguments: [
                           "new-surface", "--type", "terminal", "--focus", "true", "--command", "herdr session attach x",
                           "--id-format", "uuids", "--window", "window:2", "--workspace", "workspace:14", "--pane", "pane:15"]))
        let empty = CmuxLayout(surfaces: [], activeWindow: nil, activeWorkspace: nil, activePane: nil)
        XCTAssertEqual(CmuxCommand.open(cmux: "/c", layout: empty, command: "x"),
                       HostCommand(executable: "/c", arguments: [
                           "new-surface", "--type", "terminal", "--focus", "true", "--command", "x",
                           "--id-format", "uuids"]))
    }

    /// cmux 0.64 reports no tty for a tab opened since some point — every tab
    /// Herdview opens among them — so a terminal is kept without one, by id.
    func testTerminalWithoutTTYIsKeptWithItsId() throws {
        let text = """
        {"windows":[{"ref":"window:1","workspaces":[{"ref":"workspace:5","panes":[{"ref":"pane:3","surfaces":[
          {"ref":"surface:251","id":"F35EBAF5-3461-41FC-9B74-543D454792B2","tty":null,"type":"terminal"},
          {"ref":"surface:10","id":"AAAA","tty":"ttys003","type":"terminal"},
          {"ref":"surface:11","id":"BBBB","tty":null,"type":"browser"}
        ]}]}]}]}
        """
        let layout = try CmuxLayout.parse(tree: Data(text.utf8))
        XCTAssertEqual(layout.surfaces, [
            CmuxSurface(ref: "surface:251", id: "F35EBAF5-3461-41FC-9B74-543D454792B2", tty: nil,
                        workspaceRef: "workspace:5", windowRef: "window:1"),
            CmuxSurface(ref: "surface:10", id: "AAAA", tty: "ttys003", workspaceRef: "workspace:5", windowRef: "window:1"),
        ])
    }

    func testOpenedSurfaceIdIsTheFirstWordAfterOK() {
        XCTAssertEqual(CmuxCommand.openedSurfaceId(
            output: "OK FBA119D0-A506-44B3-B406-1B8C2654B390 7D4E7888-F8A7-495D-A4D4-60E23F43270C 8AC35770-9DE1\n"),
            "FBA119D0-A506-44B3-B406-1B8C2654B390")
        XCTAssertNil(CmuxCommand.openedSurfaceId(output: ""))
        XCTAssertNil(CmuxCommand.openedSurfaceId(output: "Error: nope"))
    }
}
