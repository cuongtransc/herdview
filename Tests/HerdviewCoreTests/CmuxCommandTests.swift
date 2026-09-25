import XCTest
@testable import HerdviewCore

final class CmuxCommandTests: XCTestCase {
    func testFailureIsTheLastStderrLine() {
        XCTAssertEqual(CmuxCommand.failure(stderr: "warming up\n  no such panel  \n", exitCode: 1), "no such panel")
    }

    func testFailureWithoutStderrIsTheExitCode() {
        XCTAssertEqual(CmuxCommand.failure(stderr: "", exitCode: 3), "exit 3")
        XCTAssertEqual(CmuxCommand.failure(stderr: "\n \n", exitCode: 3), "exit 3")
    }

    /// As cmux 2026-09 prints it when its socket is in "cmux processes only"
    /// mode and the caller was launched from the Dock or Finder.
    func testAccessDeniedSaysHowToLetHerdviewIn() {
        let stderr = "Error: ERROR: Access denied - only processes started inside cmux can connect\n"
        XCTAssertEqual(CmuxCommand.failure(stderr: stderr, exitCode: 1),
                       "cmux only lets in apps started inside it — set Settings › Automation to Password, or run `mise run cmux:setup`")
    }
}
