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

    // MARK: - A tab Herdview opened, which cmux gives no tty

    private func unknownTTY(_ n: Int, id: String) -> CmuxSurface {
        CmuxSurface(ref: "surface:\(n)", id: id, tty: nil, workspaceRef: "workspace:1", windowRef: "window:1")
    }

    func testRememberedTabIsFocusedWhenNoTTYMatches() {
        let tab = unknownTTY(251, id: "F35E")
        XCTAssertEqual(Jump.route(host: hms, session: "default", clients: [],
                                  layout: layout([surface(1, tty: "ttys001"), tab]), remembered: "F35E"),
                       .focus(tab))
    }

    func testTTYMatchWinsOverTheRememberedTab() {
        let byTTY = surface(2, tty: "ttys017")
        XCTAssertEqual(Jump.route(host: hms, session: "default",
                                  clients: [AttachClient(tty: "ttys017", sshTarget: "ct-hms-lan", session: "default")],
                                  layout: layout([unknownTTY(251, id: "F35E"), byTTY]), remembered: "F35E"),
                       .focus(byTTY))
    }

    func testRememberedTabThatIsGoneOpensOne() {
        XCTAssertEqual(Jump.route(host: hms, session: "default", clients: [],
                                  layout: layout([unknownTTY(9, id: "OTHER")]), remembered: "F35E"),
                       .open)
    }
}
