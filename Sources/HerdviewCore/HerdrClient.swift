import Foundation

/// Typed calls over `HerdrSocketClient`.
public enum HerdrClient {
    public static func agentList(socketPath: String) throws -> [AgentInfo] {
        let id = "herdview-\(UUID().uuidString.prefix(8))"
        let line = try HerdrProtocol.requestLine(id: id, method: "agent.list")
        let response = try HerdrSocketClient.exchange(line: line, socketPath: socketPath)
        return try HerdrProtocol.decodeResult(response, as: AgentListResult.self).agents
    }

    /// Focuses the Agent's pane inside its Session. Throws `HerdrError` when
    /// Herdr no longer knows the pane.
    public static func agentFocus(socketPath: String, paneId: String) throws {
        let id = "herdview-\(UUID().uuidString.prefix(8))"
        let line = try HerdrProtocol.requestLine(id: id, method: "agent.focus", params: AgentTarget(target: paneId))
        let response = try HerdrSocketClient.exchange(line: line, socketPath: socketPath)
        _ = try HerdrProtocol.decodeResult(response, as: OkResult.self)
    }
}
