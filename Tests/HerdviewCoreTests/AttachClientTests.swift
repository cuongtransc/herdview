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
