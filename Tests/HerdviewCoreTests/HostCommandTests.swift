import XCTest
@testable import HerdviewCore

final class HostCommandTests: XCTestCase {
    func testLocalHostRunsHerdrDirectly() {
        let host = HostConfig(name: "local", ssh: nil, herdrPath: "/opt/homebrew/bin/herdr", pollSeconds: 2)
        XCTAssertEqual(HostCommand.sessionList(for: host), HostCommand(executable: "/opt/homebrew/bin/herdr", arguments: ["session", "list", "--json"]))
    }

    func testRemoteHostRunsOverSSH() {
        let host = HostConfig(name: "devtuf", ssh: "cuongnb@devtuf", herdrPath: "/home/cuongnb/.local/bin/herdr", pollSeconds: 2)
        XCTAssertEqual(HostCommand.sessionList(for: host), HostCommand(
            executable: "/usr/bin/ssh",
            arguments: ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "cuongnb@devtuf", "/home/cuongnb/.local/bin/herdr session list --json"]))
    }

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
}
