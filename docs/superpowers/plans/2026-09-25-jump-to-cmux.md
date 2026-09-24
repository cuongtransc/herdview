# Jump to an Agent in cmux Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Double-clicking an Agent's row focuses the Agent's pane in Herdr and brings the cmux tab attached to its Session forward, or opens one — for local and remote Hosts.

**Architecture:** All parsing and decisions live in `HerdviewCore` as pure, unit-tested functions: `AttachClient` (reads `ps`), `CmuxLayout` (reads `cmux tree --all --json`), `Jump.route` (picks focus vs open), `CmuxCommand` / `HostCommand.attach` (build argv), `HerdrClient.agentFocus` (socket call). The App target adds one `SessionJumper` that runs them off the main thread, a socket-path registry and a transient error on `AgentStore`, and a double-click gesture on the row.

**Tech Stack:** Swift 5.10 package, macOS 13+, SwiftUI + AppKit, XCTest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-25-jump-to-cmux-design.md`

## Global Constraints

- Platform floor stays macOS 13 (`Package.swift` `.macOS(.v13)`); no new package dependencies.
- Every executable is run by absolute path (a GUI app has no useful PATH): `/usr/bin/ssh`, `/bin/ps`, the configured `herdr_path`, the resolved cmux path.
- Every subprocess of a Jump has a 5 second timeout (`ProcessRunner.run(_:timeoutSeconds: 5)`).
- A new remote tab runs `/usr/bin/ssh -t <ssh> '<herdr_path> session attach <session>'`; a new local tab runs `<herdr_path> session attach <session>`.
- Recognising an existing tab accepts both `ssh … <herdr> session attach S` and `herdr --remote T [--session S]`, plus local `herdr`, `herdr --session S`, `herdr session attach S`.
- A remote Host matches a client only when `sshTarget == host.ssh` exactly.
- `agent.focus` params are `{"target": "<pane_id>"}`; success result is `{"type":"ok"}`; failure is logged and the Jump continues.
- Errors show with the existing `Notice` at the top of the list and clear after 5 seconds or on the next Jump. Copy: `cmux not found — set cmux_path in <config path>`, `cmux <command>: <last stderr line>`.
- Double-click only; single click does nothing; rows get no hover highlight.
- `cmux_path` is an optional top-level config key, above the first `[[hosts]]`. Unset: first executable of `/opt/homebrew/bin/cmux`, `/usr/local/bin/cmux`, `/Applications/cmux.app/Contents/Resources/bin/cmux`.
- cmux bundle id: `com.cmuxterm.app`.
- Match surrounding code style: doc comments explain *why*, `public` API in Core, `@testable import HerdviewCore` in tests.

## Review Focus

- Same Session name on two Hosts (`default` locally and on `ct-hms-lan`): a Jump must never focus the other Host's tab. Pinned in Task 4 (`testSameSessionNameOnAnotherHostDoesNotMatch`).
- ssh options before the target (`ssh -p 2222 -o X=Y host …`, `ssh -tt host …`, `ssh -lubuntu host …`): target still found. Pinned in Task 2.
- Session name with a space or quote: the remote attach command must reach the remote shell as one word. Pinned in Task 4 (`testRemoteAttachQuotesSessionForTheRemoteShell`); recognising such a tab afterwards is not supported (ps loses quoting) and opens a new tab instead.
- Herdview's own `ssh -N -L …` forwards and herdr's `remote-client-bridge` ssh child must never count as a client. Pinned in Task 2.
- A double-click while a Jump is still running must not open a second tab. Covered by `SessionJumper.running` in Task 6 and the manual check there.

---

### Task 1: `agent.focus` over the socket

**Files:**
- Modify: `Sources/HerdviewCore/HerdrProtocol.swift`
- Modify: `Sources/HerdviewCore/HerdrClient.swift`
- Test: `Tests/HerdviewCoreTests/HerdrProtocolTests.swift`

**Interfaces:**
- Consumes: `HerdrSocketClient.exchange(line:socketPath:timeoutSeconds:)` (existing).
- Produces:
  - `HerdrProtocol.requestLine<P: Encodable>(id: String, method: String, params: P) throws -> Data`
  - `public struct AgentTarget: Encodable, Equatable, Sendable { public let target: String; public init(target: String) }`
  - `public struct OkResult: Decodable, Equatable, Sendable { public let type: String }`
  - `HerdrClient.agentFocus(socketPath: String, paneId: String) throws`

- [ ] **Step 1: Write the failing tests** — append to `HerdrProtocolTests`:

```swift
    func testRequestLineCarriesParams() throws {
        let line = try HerdrProtocol.requestLine(id: "req_2", method: "agent.focus",
                                                 params: AgentTarget(target: "w1:p3"))
        XCTAssertEqual(line.last, 0x0A)
        let obj = try JSONSerialization.jsonObject(with: line.dropLast()) as? [String: Any]
        XCTAssertEqual(obj?["method"] as? String, "agent.focus")
        XCTAssertEqual((obj?["params"] as? [String: Any])?["target"] as? String, "w1:p3")
    }

    func testDecodeOkResult() throws {
        let line = Data(#"{"id":"r","result":{"type":"ok"}}"#.utf8)
        XCTAssertEqual(try HerdrProtocol.decodeResult(line, as: OkResult.self).type, "ok")
    }

    /// The error Herdr 0.9.1 really sends for a pane that is gone.
    func testFocusOfMissingAgentThrowsHerdrError() {
        let line = Data(#"{"id":"t1","error":{"code":"agent_not_found","message":"agent target nope:p0 not found"}}"#.utf8)
        XCTAssertThrowsError(try HerdrProtocol.decodeResult(line, as: OkResult.self)) { error in
            XCTAssertEqual((error as? HerdrError)?.code, "agent_not_found")
        }
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter HerdrProtocolTests 2>&1 | tail -20`
Expected: compile error — `AgentTarget` / `OkResult` / `requestLine(id:method:params:)` not found.

- [ ] **Step 3: Implement** — in `HerdrProtocol.swift`, add the two types above `HerdrProtocol` and make `Request` generic:

```swift
/// Params of every call that names one Agent: `{"target": "<pane_id>"}`.
public struct AgentTarget: Encodable, Equatable, Sendable {
    public let target: String

    public init(target: String) {
        self.target = target
    }
}

/// The result of a call that only acknowledges: `{"type":"ok"}`.
public struct OkResult: Decodable, Equatable, Sendable {
    public let type: String
}
```

Replace the `Request` struct and `requestLine` in `HerdrProtocol` with:

```swift
    private struct Request<P: Encodable>: Encodable {
        let id: String
        let method: String
        let params: P
    }

    /// One request line, newline terminated, with empty `params`.
    public static func requestLine(id: String, method: String) throws -> Data {
        try requestLine(id: id, method: method, params: EmptyParams())
    }

    /// One request line, newline terminated.
    public static func requestLine<P: Encodable>(id: String, method: String, params: P) throws -> Data {
        var data = try JSONEncoder().encode(Request(id: id, method: method, params: params))
        data.append(0x0A)
        return data
    }
```

In `HerdrClient.swift` add:

```swift
    /// Focuses the Agent's pane inside its Session. Throws `HerdrError` when
    /// Herdr no longer knows the pane.
    public static func agentFocus(socketPath: String, paneId: String) throws {
        let id = "herdview-\(UUID().uuidString.prefix(8))"
        let line = try HerdrProtocol.requestLine(id: id, method: "agent.focus", params: AgentTarget(target: paneId))
        let response = try HerdrSocketClient.exchange(line: line, socketPath: socketPath)
        _ = try HerdrProtocol.decodeResult(response, as: OkResult.self)
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter HerdrProtocolTests 2>&1 | tail -20`
Expected: all `HerdrProtocolTests` pass, including the existing empty-params test.

- [ ] **Step 5: Commit**

```bash
git add Sources/HerdviewCore/HerdrProtocol.swift Sources/HerdviewCore/HerdrClient.swift Tests/HerdviewCoreTests/HerdrProtocolTests.swift
git commit -m "feat(jump): focus an Agent over the Herdr socket"
```

---

### Task 2: `AttachClient` — which terminal is attached to which Session

**Files:**
- Create: `Sources/HerdviewCore/AttachClient.swift`
- Test: `Tests/HerdviewCoreTests/AttachClientTests.swift`

**Interfaces:**
- Produces:
  - `public struct AttachClient: Equatable, Sendable { tty: String; sshTarget: String?; session: String; init(tty:sshTarget:session:) }`
  - `AttachClient.parse(ps: String) -> [AttachClient]` — input is `ps -axo pid=,tty=,command=` output.

- [ ] **Step 1: Write the failing tests** — `Tests/HerdviewCoreTests/AttachClientTests.swift`:

```swift
import XCTest
@testable import HerdviewCore

/// Lines are taken from a real `ps -axo pid=,tty=,command=` on 2026-09-25 with
/// both remote attach forms open against `ct-hms-lan`.
final class AttachClientTests: XCTestCase {
    private func parse(_ lines: String...) -> [AttachClient] {
        AttachClient.parse(ps: lines.joined(separator: "\n"))
    }

    func testLocalClientForms() {
        XCTAssertEqual(parse(
            "  101 ttys001  /Users/me/.local/bin/herdr",
            "  102 ttys002  herdr --session work",
            "  103 ttys003  /opt/homebrew/bin/herdr session attach wd-bmf"
        ), [
            AttachClient(tty: "ttys001", sshTarget: nil, session: "default"),
            AttachClient(tty: "ttys002", sshTarget: nil, session: "work"),
            AttachClient(tty: "ttys003", sshTarget: nil, session: "wd-bmf"),
        ])
    }

    func testSSHAttachIsARemoteClient() {
        XCTAssertEqual(parse(
            "83553 ttys017  ssh -t ct-hms-lan /home/ubuntu/.local/bin/herdr session attach wd-bmf"
        ), [AttachClient(tty: "ttys017", sshTarget: "ct-hms-lan", session: "wd-bmf")])
    }

    func testHerdrRemoteIsARemoteClient() {
        XCTAssertEqual(parse(
            "83525 ttys020  herdr --remote ct-hms-lan --session wd-bmf",
            "83526 ttys021  /Users/me/.local/bin/herdr --remote devtuf"
        ), [
            AttachClient(tty: "ttys020", sshTarget: "ct-hms-lan", session: "wd-bmf"),
            AttachClient(tty: "ttys021", sshTarget: "devtuf", session: "default"),
        ])
    }

    func testSSHOptionsBeforeTheTargetAreSkipped() {
        XCTAssertEqual(parse(
            "1 ttys001  /usr/bin/ssh -p 2222 -o ServerAliveInterval=15 box herdr session attach a",
            "2 ttys002  ssh -tt box /x/herdr session attach b",
            "3 ttys003  ssh -lubuntu -A box /x/herdr session attach c",
            "4 ttys004  ssh -tp 22 box /x/herdr session attach d",
            "5 ttys005  ssh -- box /x/herdr session attach e"
        ).map { "\($0.sshTarget ?? "-") \($0.session)" }, [
            "box a", "box b", "box c", "box d", "box e",
        ])
    }

    func testProcessesThatAreNotClientsAreSkipped() {
        XCTAssertEqual(parse(
            // herdr --remote's own ssh child, on the same tty as its parent
            "83682 ttys020  ssh -F /tmp/herdr-ssh/config -S /tmp/herdr-ssh/ctl -o ControlMaster=auto -T ct-hms-lan printf '\\012%s\\012' 'herdr-remote-output-ready:1'\\012exec /home/ubuntu/.local/bin/herdr --session wd-bmf remote-client-bridge",
            // Herdview's socket forward, even if it ever had a tty
            "  200 ttys009  /usr/bin/ssh -N -o BatchMode=yes -L /a.sock:/b.sock devtuf",
            // an interactive ssh with no remote command
            "95744 ttys013  ssh ct-hms-lan",
            // the server and one-shot API calls
            "  300 ??       /opt/homebrew/bin/herdr server",
            "  301 ttys010  herdr server",
            "  302 ttys010  herdr --session work agent list",
            "  303 ttys010  herdr --machine box",
            // not herdr or ssh at all
            "  400 ttys011  -zsh",
            // no terminal
            "  500 ??       herdr session attach x",
            // malformed
            "garbage",
            ""
        ), [])
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter AttachClientTests 2>&1 | tail -20`
Expected: compile error — `AttachClient` not found.

- [ ] **Step 3: Implement** — `Sources/HerdviewCore/AttachClient.swift`:

```swift
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
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter AttachClientTests 2>&1 | tail -20`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/HerdviewCore/AttachClient.swift Tests/HerdviewCoreTests/AttachClientTests.swift
git commit -m "feat(jump): read attached Herdr clients from ps"
```

---

### Task 3: `CmuxLayout` and `CmuxCommand`

**Files:**
- Create: `Sources/HerdviewCore/CmuxLayout.swift`
- Create: `Sources/HerdviewCore/CmuxCommand.swift`
- Test: `Tests/HerdviewCoreTests/CmuxLayoutTests.swift`

**Interfaces:**
- Consumes: `HostCommand(executable:arguments:)` (existing).
- Produces:
  - `public struct CmuxSurface: Equatable, Sendable { ref, tty, workspaceRef, windowRef: String; init(ref:tty:workspaceRef:windowRef:) }`
  - `public struct CmuxLayout: Equatable, Sendable { surfaces: [CmuxSurface]; activeWindow, activeWorkspace, activePane: String?; init(surfaces:activeWindow:activeWorkspace:activePane:) }`
  - `CmuxLayout.parse(tree: Data) throws -> CmuxLayout` (throws `CmuxError.unexpectedOutput`)
  - `public enum CmuxError: Error, Equatable, CustomStringConvertible { case unexpectedOutput }`
  - `CmuxCommand.tree(cmux: String) -> HostCommand`
  - `CmuxCommand.focus(cmux: String, surface: CmuxSurface) -> HostCommand`
  - `CmuxCommand.open(cmux: String, layout: CmuxLayout, command: String) -> HostCommand`

- [ ] **Step 1: Write the failing tests** — `Tests/HerdviewCoreTests/CmuxLayoutTests.swift`:

```swift
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
                       HostCommand(executable: "/c", arguments: ["tree", "--all", "--json"]))
        XCTAssertEqual(CmuxCommand.focus(cmux: "/c", surface: surface),
                       HostCommand(executable: "/c", arguments: [
                           "focus-panel", "--panel", "surface:190", "--workspace", "workspace:14", "--window", "window:2"]))
        let full = CmuxLayout(surfaces: [], activeWindow: "window:2", activeWorkspace: "workspace:14", activePane: "pane:15")
        XCTAssertEqual(CmuxCommand.open(cmux: "/c", layout: full, command: "herdr session attach x"),
                       HostCommand(executable: "/c", arguments: [
                           "new-surface", "--type", "terminal", "--focus", "true", "--command", "herdr session attach x",
                           "--window", "window:2", "--workspace", "workspace:14", "--pane", "pane:15"]))
        let empty = CmuxLayout(surfaces: [], activeWindow: nil, activeWorkspace: nil, activePane: nil)
        XCTAssertEqual(CmuxCommand.open(cmux: "/c", layout: empty, command: "x"),
                       HostCommand(executable: "/c", arguments: [
                           "new-surface", "--type", "terminal", "--focus", "true", "--command", "x"]))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter CmuxLayoutTests 2>&1 | tail -20`
Expected: compile error — `CmuxLayout` not found.

- [ ] **Step 3: Implement** — `Sources/HerdviewCore/CmuxLayout.swift`:

```swift
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
```

`Sources/HerdviewCore/CmuxCommand.swift`:

```swift
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
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter CmuxLayoutTests 2>&1 | tail -20`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/HerdviewCore/CmuxLayout.swift Sources/HerdviewCore/CmuxCommand.swift Tests/HerdviewCoreTests/CmuxLayoutTests.swift
git commit -m "feat(jump): read the cmux layout and build cmux calls"
```

---

### Task 4: Attach command and `Jump.route`

**Files:**
- Modify: `Sources/HerdviewCore/HostCommand.swift`
- Create: `Sources/HerdviewCore/Jump.swift`
- Test: `Tests/HerdviewCoreTests/HostCommandTests.swift`
- Test: `Tests/HerdviewCoreTests/JumpRouteTests.swift`

**Interfaces:**
- Consumes: `AttachClient` (Task 2), `CmuxSurface`, `CmuxLayout` (Task 3), `HostConfig` (existing, `ssh: String?`, `herdrPath: String`).
- Produces:
  - `HostCommand.attach(for host: HostConfig, session: String) -> HostCommand`
  - `HostCommand.shellLine: String` — the command as one shell-quoted line.
  - `public enum JumpRoute: Equatable, Sendable { case focus(CmuxSurface); case open }`
  - `Jump.route(host: HostConfig, session: String, clients: [AttachClient], layout: CmuxLayout) -> JumpRoute`

- [ ] **Step 1: Write the failing tests** — append to `HostCommandTests`:

```swift
    func testLocalAttach() {
        let host = HostConfig(name: "local", ssh: nil, herdrPath: "/Users/me/.local/bin/herdr", pollSeconds: 2)
        let command = HostCommand.attach(for: host, session: "wd-bmf")
        XCTAssertEqual(command, HostCommand(executable: "/Users/me/.local/bin/herdr",
                                            arguments: ["session", "attach", "wd-bmf"]))
        XCTAssertEqual(command.shellLine, "/Users/me/.local/bin/herdr session attach wd-bmf")
    }

    func testRemoteAttachRunsInATerminalOverSSH() {
        let host = HostConfig(name: "hms", ssh: "ct-hms-lan", herdrPath: "/home/ubuntu/.local/bin/herdr", pollSeconds: 2)
        let command = HostCommand.attach(for: host, session: "wd-bmf")
        XCTAssertEqual(command, HostCommand(executable: "/usr/bin/ssh", arguments: [
            "-t", "ct-hms-lan", "/home/ubuntu/.local/bin/herdr session attach wd-bmf"]))
        XCTAssertEqual(command.shellLine,
                       "/usr/bin/ssh -t ct-hms-lan '/home/ubuntu/.local/bin/herdr session attach wd-bmf'")
    }

    /// ssh joins its remote words with spaces and the remote shell splits them
    /// again, so the Session name is quoted once for each shell.
    func testRemoteAttachQuotesSessionForTheRemoteShell() {
        let host = HostConfig(name: "hms", ssh: "ct-hms-lan", herdrPath: "/h/herdr", pollSeconds: 2)
        let command = HostCommand.attach(for: host, session: "it's mine")
        XCTAssertEqual(command.arguments.last, #"/h/herdr session attach 'it'\''s mine'"#)
        XCTAssertEqual(command.shellLine,
                       #"/usr/bin/ssh -t ct-hms-lan '/h/herdr session attach '\''it'\''\'\'''\''s mine'\'''"#)
    }

    func testShellLineQuotesOnlyWhatNeedsIt() {
        XCTAssertEqual(HostCommand(executable: "/a b/c", arguments: ["x", "", "y=1,2:3@h"]).shellLine,
                       "'/a b/c' x '' y=1,2:3@h")
    }
```

`Tests/HerdviewCoreTests/JumpRouteTests.swift`:

```swift
import XCTest
@testable import HerdviewCore

final class JumpRouteTests: XCTestCase {
    private let local = HostConfig(name: "local", ssh: nil, herdrPath: "/h", pollSeconds: 2)
    private let hms = HostConfig(name: "hms", ssh: "ct-hms-lan", herdrPath: "/h", pollSeconds: 2)

    private func surface(_ n: Int, tty: String, window: String = "window:1") -> CmuxSurface {
        CmuxSurface(ref: "surface:\(n)", tty: tty, workspaceRef: "workspace:1", windowRef: window)
    }

    private func layout(_ surfaces: [CmuxSurface], active: String? = "window:1") -> CmuxLayout {
        CmuxLayout(surfaces: surfaces, activeWindow: active, activeWorkspace: nil, activePane: nil)
    }

    func testLocalClientsTabIsFocused() {
        let tab = surface(1, tty: "ttys001")
        XCTAssertEqual(Jump.route(host: local, session: "work",
                                  clients: [AttachClient(tty: "ttys001", sshTarget: nil, session: "work")],
                                  layout: layout([surface(9, tty: "ttys009"), tab])),
                       .focus(tab))
    }

    func testRemoteClientMatchesBySSHTarget() {
        let tab = surface(2, tty: "ttys017")
        XCTAssertEqual(Jump.route(host: hms, session: "wd-bmf",
                                  clients: [AttachClient(tty: "ttys017", sshTarget: "ct-hms-lan", session: "wd-bmf")],
                                  layout: layout([tab])),
                       .focus(tab))
    }

    func testSameSessionNameOnAnotherHostDoesNotMatch() {
        let clients = [
            AttachClient(tty: "ttys001", sshTarget: nil, session: "default"),
            AttachClient(tty: "ttys002", sshTarget: "other-box", session: "default"),
        ]
        let tabs = layout([surface(1, tty: "ttys001"), surface(2, tty: "ttys002")])
        XCTAssertEqual(Jump.route(host: hms, session: "default", clients: clients, layout: tabs), .open)
        XCTAssertEqual(Jump.route(host: local, session: "default", clients: clients, layout: tabs),
                       .focus(surface(1, tty: "ttys001")))
    }

    func testSeveralTabsPreferTheActiveWindow() {
        let clients = [
            AttachClient(tty: "ttys001", sshTarget: nil, session: "work"),
            AttachClient(tty: "ttys002", sshTarget: nil, session: "work"),
        ]
        let other = surface(1, tty: "ttys001", window: "window:1")
        let here = surface(2, tty: "ttys002", window: "window:2")
        XCTAssertEqual(Jump.route(host: local, session: "work", clients: clients,
                                  layout: layout([other, here], active: "window:2")), .focus(here))
        XCTAssertEqual(Jump.route(host: local, session: "work", clients: clients,
                                  layout: layout([other, here], active: "window:9")), .focus(other))
    }

    func testNoTabOpensOne() {
        XCTAssertEqual(Jump.route(host: local, session: "work", clients: [], layout: layout([surface(1, tty: "ttys001")])),
                       .open)
        // A client whose terminal is not a cmux tab (Terminal.app, say) is not a tab to focus.
        XCTAssertEqual(Jump.route(host: local, session: "work",
                                  clients: [AttachClient(tty: "ttys005", sshTarget: nil, session: "work")],
                                  layout: layout([surface(1, tty: "ttys001")])),
                       .open)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter 'HostCommandTests|JumpRouteTests' 2>&1 | tail -20`
Expected: compile error — `attach(for:session:)`, `shellLine`, `Jump` not found.

- [ ] **Step 3: Implement** — add to `HostCommand` in `HostCommand.swift`:

```swift
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
```

`Sources/HerdviewCore/Jump.swift`:

```swift
import Foundation

/// How a Jump brings a Session forward in cmux.
public enum JumpRoute: Equatable, Sendable {
    /// A tab is already attached to the Session: focus it.
    case focus(CmuxSurface)
    /// No tab is: open one attached to it.
    case open
}

public enum Jump {
    /// Finds the cmux tab attached to `session` on `host`. A client matches
    /// only on the same Host: a local Host takes local clients, a remote one
    /// takes clients whose ssh target is the Host's `ssh` exactly, so a
    /// `default` Session on one machine never answers for another's. With
    /// several tabs, the one in the window the person is looking at wins.
    public static func route(host: HostConfig, session: String,
                             clients: [AttachClient], layout: CmuxLayout) -> JumpRoute {
        let ttys = Set(clients.filter { $0.session == session && $0.sshTarget == host.ssh }.map(\.tty))
        let tabs = layout.surfaces.filter { ttys.contains($0.tty) }
        guard let first = tabs.first else { return .open }
        return .focus(tabs.first { $0.windowRef == layout.activeWindow } ?? first)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter 'HostCommandTests|JumpRouteTests' 2>&1 | tail -20`
Expected: all pass. If `testRemoteAttachQuotesSessionForTheRemoteShell`'s `shellLine` literal disagrees, verify by hand that the implementation is right — `zsh -c "print -r -- <shellLine minus /usr/bin/ssh -t ct-hms-lan>"` must print `/h/herdr session attach 'it'\''s mine'` — and correct the literal, not the quoting function.

- [ ] **Step 5: Commit**

```bash
git add Sources/HerdviewCore/HostCommand.swift Sources/HerdviewCore/Jump.swift Tests/HerdviewCoreTests/HostCommandTests.swift Tests/HerdviewCoreTests/JumpRouteTests.swift
git commit -m "feat(jump): route a Jump to an existing tab or a new attach"
```

---

### Task 5: `cmux_path` config

**Files:**
- Modify: `Sources/HerdviewCore/HerdviewConfig.swift`
- Test: `Tests/HerdviewCoreTests/ConfigLoaderTests.swift`

**Interfaces:**
- Produces:
  - `HerdviewConfig.cmuxPath: String?` and `HerdviewConfig.init(hosts:hiddenProviders:cmuxPath:)` with `cmuxPath: String? = nil`.
  - `ConfigLoader.findCmux(isExecutable: (String) -> Bool = FileManager.default.isExecutableFile) -> String?`

- [ ] **Step 1: Write the failing tests** — append to `ConfigLoaderTests`:

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ConfigLoaderTests 2>&1 | tail -20`
Expected: compile error — `cmuxPath` / `findCmux` not found.

- [ ] **Step 3: Implement** — in `HerdviewConfig`, add the property and extend the initialiser (keep the existing doc comments):

```swift
    /// Where `cmux` is, from `cmux_path`; nil means look in the usual places.
    public var cmuxPath: String?

    public init(hosts: [HostConfig], hiddenProviders: Set<QuotaProvider> = [], cmuxPath: String? = nil) {
        self.hosts = hosts
        self.hiddenProviders = hiddenProviders
        self.cmuxPath = cmuxPath
    }
```

In `ConfigLoader`, after `findHerdr`, add:

```swift
    /// Where `cmux` is on this Mac, for a Jump. Unlike `findHerdr` there is no
    /// fallback: with no cmux a Jump says so instead of running a path that is
    /// not there.
    public static func findCmux(
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        ["/opt/homebrew/bin/cmux", "/usr/local/bin/cmux", "/Applications/cmux.app/Contents/Resources/bin/cmux"]
            .first(where: isExecutable)
    }
```

In `ConfigLoader.parse`, after the `hidden_providers` block:

```swift
        var cmuxPath: String?
        if let raw = doc.root["cmux_path"] {
            guard let value = raw.stringValue else { throw ConfigError.invalidType("cmux_path must be a string") }
            cmuxPath = value
        }
```

and change the return to `return HerdviewConfig(hosts: hosts, hiddenProviders: hidden, cmuxPath: cmuxPath)`.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter ConfigLoaderTests 2>&1 | tail -20`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/HerdviewCore/HerdviewConfig.swift Tests/HerdviewCoreTests/ConfigLoaderTests.swift
git commit -m "feat(jump): read cmux_path and find cmux"
```

---

### Task 6: `SessionJumper`, row double-click, README

No App test target exists; this task is verified by build, the UI shots gate and a manual run.

**Files:**
- Create: `Sources/App/SessionJumper.swift`
- Modify: `Sources/App/AgentStore.swift`
- Modify: `Sources/App/SessionWatcher.swift` (`start()`, `stop()`)
- Modify: `Sources/App/AppDelegate.swift` (property list; after `monitor.start()`)
- Modify: `Sources/App/AgentListView.swift` (notices block ~line 86; `HostGroup`; `AgentRow`; `wash` doc comment ~line 354; `tooltip`)
- Modify: `README.md`

**Interfaces:**
- Consumes: `HerdrClient.agentFocus(socketPath:paneId:)` (Task 1); `AttachClient.parse(ps:)` (Task 2); `CmuxLayout.parse(tree:)`, `CmuxError`, `CmuxCommand.tree/focus/open` (Task 3); `HostCommand.attach(for:session:)`, `.shellLine`, `Jump.route(host:session:clients:layout:)`, `JumpRoute` (Task 4); `HerdviewConfig.cmuxPath`, `ConfigLoader.findCmux()` (Task 5); `ProcessRunner.run(_:timeoutSeconds:)`, `ProcessRunnerError` (existing).
- Produces: `AgentStore.jumpAction`, `AgentStore.jumpError`, `AgentStore.showJumpError(_:)`, `AgentStore.setSocketPath(_:host:session:)`, `AgentStore.socketPath(host:session:)`, `SessionJumper.jump(_:)`.

- [ ] **Step 1: `AgentStore`** — add below `configError`:

```swift
    /// What a double-click on an Agent's row does. Set once the config is read;
    /// nil (the UI shots) makes the double-click do nothing.
    var jumpAction: ((TrackedAgent) -> Void)?
    /// Why the last Jump failed, shown above the list until it clears itself.
    @Published private(set) var jumpError: String?
    private var jumpErrorClear: Task<Void, Never>?
    /// The socket each watched Session is reached on, by `host/session`: the
    /// Session's own for this Mac, the forwarded one for a remote Host.
    private var socketPaths: [String: String] = [:]

    func setSocketPath(_ path: String?, host: String, session: String) {
        socketPaths["\(host)/\(session)"] = path
    }

    func socketPath(host: String, session: String) -> String? {
        socketPaths["\(host)/\(session)"]
    }

    /// Shows `message` for five seconds; nil clears it at once. A Jump is a
    /// thing that happened, not a state of the herd, so it does not stay.
    func showJumpError(_ message: String?) {
        jumpErrorClear?.cancel()
        jumpError = message
        guard message != nil else { return }
        jumpErrorClear = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.jumpError = nil
        }
    }
```

- [ ] **Step 2: `SessionWatcher`** — first line of `start()`: `store.setSocketPath(socketPath, host: host.name, session: session.name)`. In `stop()`, before `store.removeSession(...)`: `store.setSocketPath(nil, host: host.name, session: session.name)`.

- [ ] **Step 3: `SessionJumper`** — `Sources/App/SessionJumper.swift`:

```swift
import AppKit
import HerdviewCore

/// Brings an Agent to the front: its pane focused inside Herdr, and the cmux
/// tab attached to its Session forward — or a new tab attached to it.
///
/// One Jump at a time. A double-click that lands while the last one is still
/// asking cmux would otherwise see no tab yet and open a second one.
@MainActor
final class SessionJumper {
    private static let timeoutSeconds: Double = 5
    private static let cmuxBundleId = "com.cmuxterm.app"
    private static let ps = HostCommand(executable: "/bin/ps", arguments: ["-axo", "pid=,tty=,command="])

    private enum JumpError: Error, CustomStringConvertible {
        case cmux(String, String)
        var description: String {
            switch self {
            case .cmux(let command, let detail): return "cmux \(command): \(detail)"
            }
        }
    }

    private let hosts: [String: HostConfig]
    private let cmuxPath: String?
    private let store: AgentStore
    private var running = false

    init(hosts: [HostConfig], cmuxPath: String?, store: AgentStore) {
        self.hosts = Dictionary(hosts.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        self.cmuxPath = cmuxPath
        self.store = store
    }

    func jump(_ agent: TrackedAgent) {
        guard !running, let host = hosts[agent.host] else { return }
        guard let cmux = cmuxPath else {
            store.showJumpError("cmux not found — set cmux_path in \(ConfigLoader.defaultPath)")
            return
        }
        running = true
        store.showJumpError(nil)
        let socketPath = store.socketPath(host: agent.host, session: agent.session)
        Task {
            defer { running = false }
            await focusPane(agent, socketPath: socketPath)
            do {
                try await bringSessionForward(host: host, session: agent.session, cmux: cmux)
                activateCmux()
            } catch {
                store.showJumpError(String(describing: error))
            }
        }
    }

    /// Best effort: the Agent may have exited since the list was drawn, and
    /// landing in its Session still beats landing nowhere.
    private func focusPane(_ agent: TrackedAgent, socketPath: String?) async {
        guard let socketPath else { return }
        let paneId = agent.info.paneId
        let outcome = await Task.detached(priority: .userInitiated) {
            Result { try HerdrClient.agentFocus(socketPath: socketPath, paneId: paneId) }
        }.value
        if case .failure(let error) = outcome {
            NSLog("herdview: agent.focus %@ failed: %@", agent.key, String(describing: error))
        }
    }

    private func bringSessionForward(host: HostConfig, session: String, cmux: String) async throws {
        let layout = try CmuxLayout.parse(tree: try await run(CmuxCommand.tree(cmux: cmux), label: "tree"))
        // Without a process list no tab can be recognised; a new tab is still a Jump.
        let psOutput = try? await ProcessRunner.run(Self.ps, timeoutSeconds: Self.timeoutSeconds)
        let clients = AttachClient.parse(ps: psOutput.flatMap { String(data: $0, encoding: .utf8) } ?? "")
        switch Jump.route(host: host, session: session, clients: clients, layout: layout) {
        case .focus(let surface):
            _ = try await run(CmuxCommand.focus(cmux: cmux, surface: surface), label: "focus-panel")
        case .open:
            let attach = HostCommand.attach(for: host, session: session).shellLine
            _ = try await run(CmuxCommand.open(cmux: cmux, layout: layout, command: attach), label: "new-surface")
        }
    }

    private func run(_ command: HostCommand, label: String) async throws -> Data {
        do {
            return try await ProcessRunner.run(command, timeoutSeconds: Self.timeoutSeconds)
        } catch let error as ProcessRunnerError {
            switch error {
            case .launchFailed(let why):
                throw JumpError.cmux(label, why)
            case .nonZeroExit(let code, let stderr):
                let last = stderr.split(whereSeparator: \.isNewline).last
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                throw JumpError.cmux(label, last ?? "exit \(code)")
            }
        }
    }

    /// cmux has just been told what to show; this puts it in front of Herdview.
    private func activateCmux() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.cmuxBundleId) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error { NSLog("herdview: could not activate cmux: %@", String(describing: error)) }
        }
    }
}
```

- [ ] **Step 4: `AppDelegate`** — add `private var jumper: SessionJumper?` to the properties, and after `monitor.start()`:

```swift
        let jumper = SessionJumper(hosts: config.hosts,
                                   cmuxPath: config.cmuxPath ?? ConfigLoader.findCmux(),
                                   store: store)
        self.jumper = jumper
        store.jumpAction = { [weak jumper] in jumper?.jump($0) }
```

- [ ] **Step 5: `AgentListView`**

After the `if let error = store.configError { … }` block, add:

```swift
                            if let error = store.jumpError {
                                Notice(symbol: "exclamationmark.triangle.fill", text: error, tint: .orange)
                                    .padding(.horizontal, Metrics.textInset)
                                    .cardSurface()
                            }
```

Pass the action into each `HostGroup(...)` call: add the argument `onJump: { store.jumpAction?($0) }` after `now: context.date`. In `HostGroup` add the property `let onJump: (TrackedAgent) -> Void` (after `now`) and build rows as `AgentRow(agent: agent, now: now, onJump: { onJump(agent) })`.

In `AgentRow` add `var onJump: () -> Void = {}` after `let now: Date`, and after `.background(wash)` insert:

```swift
        // The whole row answers, not only its text: a double-click in the gap
        // before the status pill is still a double-click on this Agent.
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onJump)
```

Replace the `wash` doc comment's first paragraph with:

```swift
    /// A blocked or done row blinks for as long as it stays that way — it is
    /// asking for a person, and it keeps asking until someone comes. Every
    /// other row is plain. Rows do not light up under the pointer: a single
    /// click does nothing, and a hover highlight would promise that it did.
    /// A double-click Jumps to the Agent, which the tooltip says.
```

In `tooltip(for:)`, append the hint to both returns:

```swift
    private func tooltip(for text: AgentRowText) -> String {
        let lead = agent.info.cwd.flatMap { $0.isEmpty ? nil : $0 } ?? text.primary
        let hint = "Double-click to open in cmux"
        guard let session = text.session else { return "\(lead)\n\(text.secondary)\n\(hint)" }
        return "\(lead) · \(session)\n\(text.secondary)\n\(hint)"
    }
```

- [ ] **Step 6: Build**

Run: `swift build 2>&1 | tail -30`
Expected: `Build complete!`, no new warnings from the files touched. If `.onTapGesture(count:perform:)` rejects a `() -> Void` property, wrap it: `.onTapGesture(count: 2) { onJump() }`.

- [ ] **Step 7: README** — after the paragraph ending "Every blinking row pulses in step.", add:

```markdown
Double-click an agent's row to jump to it in [cmux](https://cmux.dev): its pane is
focused inside Herdr, and the cmux tab attached to its session comes forward. With
no such tab, a new one opens running `herdr session attach <session>` — over
`ssh -t <ssh>` for a remote host. A tab counts as attached to a remote session when
its command names the host's `ssh` value exactly, so a tab you opened with
`ssh user@box` is not recognised for a host configured as `ssh = "box"`; a new tab
opens instead. Herdview finds cmux in `/opt/homebrew/bin`, `/usr/local/bin` or
`cmux.app`; set `cmux_path` above the first `[[hosts]]` if it lives elsewhere.
```

And add `# cmux_path = "/opt/homebrew/bin/cmux"   # optional; where cmux is` to the config example block, directly under the `hidden_providers` line.

- [ ] **Step 8: Full gate**

Run: `mise run ci > /tmp/herdview-ci-$(date +%s).log 2>&1; echo "exit=$?"` (run in background; ~2 min). Then `rg -n "error:|failed|FAIL" /tmp/herdview-ci-*.log | tail -20`.
Expected: `exit=0`; all unit tests pass; UI shots checks pass.

- [ ] **Step 9: Manual check** (with the user; opens real cmux tabs)

1. Add to `~/.config/herdview/config.toml`:
   ```toml
   [[hosts]]
   name = "ct-hms-lan"
   ssh = "ct-hms-lan"
   herdr_path = "/home/ubuntu/.local/bin/herdr"
   ```
2. `mise run dev`.
3. Double-click a local Agent in a Session with no cmux tab → a new focused tab attaches to it and the Agent's pane is focused. Double-click again → the same tab comes forward; `cmux tree --all --json` shows no second tab.
4. Same for an Agent on `ct-hms-lan` (Session `wd-bmf`).
5. Double-click twice quickly on a Session with no tab → exactly one new tab.
6. Set `cmux_path = "/nope"` → double-click shows `cmux new-surface: …` or `cmux tree: …` in an orange Notice that disappears after ~5 s. Remove the key afterwards.

- [ ] **Step 10: Commit**

```bash
git add Sources/App/SessionJumper.swift Sources/App/AgentStore.swift Sources/App/SessionWatcher.swift Sources/App/AppDelegate.swift Sources/App/AgentListView.swift README.md
git commit -m "feat(jump): double-click an Agent to jump to it in cmux"
```
