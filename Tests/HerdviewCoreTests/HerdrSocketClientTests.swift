import XCTest
import Darwin
@testable import HerdviewCore

/// Accepts exactly one connection, reads one line, replies with `response` + "\n".
final class FakeSocketServer {
    let path: String
    private let fd: Int32
    private let thread: Thread

    init(response: String) {
        path = NSTemporaryDirectory() + "hp-\(UUID().uuidString.prefix(8)).sock"
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        precondition(fd >= 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let socketPath = path
        withUnsafeMutablePointer(to: &addr.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strncpy($0, socketPath, 103) }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        // `fd` is read into a local first: naming the property inside the
        // closure would capture `self` before `thread` is initialised.
        let listenFD = fd
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, len) } }
        precondition(bound == 0, "bind failed: \(String(cString: strerror(errno)))")
        precondition(listen(fd, 1) == 0)
        thread = Thread {
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { return }
            var buf = [UInt8](repeating: 0, count: 4096)
            var got = Data()
            while !got.contains(0x0A) {
                let n = read(client, &buf, buf.count)
                if n <= 0 { break }
                got.append(buf, count: n)
            }
            let out = Array((response + "\n").utf8)
            _ = out.withUnsafeBufferPointer { write(client, $0.baseAddress, $0.count) }
            close(client)
        }
        thread.start()
    }

    deinit {
        close(fd)
        unlink(path)
    }
}

final class HerdrSocketClientTests: XCTestCase {
    func testExchangeReturnsResponseLineWithoutNewline() throws {
        let server = FakeSocketServer(response: #"{"id":"req_1","result":{"type":"pong"}}"#)
        let reply = try HerdrSocketClient.exchange(line: Data("{\"id\":\"req_1\",\"method\":\"ping\",\"params\":{}}\n".utf8), socketPath: server.path)
        XCTAssertEqual(String(data: reply, encoding: .utf8), #"{"id":"req_1","result":{"type":"pong"}}"#)
    }

    func testMissingSocketIsServerNotRunning() {
        XCTAssertThrowsError(try HerdrSocketClient.exchange(line: Data("x\n".utf8), socketPath: NSTemporaryDirectory() + "hp-missing.sock")) { error in
            XCTAssertEqual(error as? HerdrClientError, .serverNotRunning)
        }
    }

    func testAgentListDecodesAgents() throws {
        let server = FakeSocketServer(response: """
        {"id":"x","result":{"type":"agent_list","agents":[{"agent_status":"blocked","workspace_id":"w1","pane_id":"w1:p1","revision":7,"agent":"codex"}]}}
        """)
        let agents = try HerdrClient.agentList(socketPath: server.path)
        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents[0].agentStatus, .blocked)
        XCTAssertEqual(agents[0].agent, "codex")
    }
}
