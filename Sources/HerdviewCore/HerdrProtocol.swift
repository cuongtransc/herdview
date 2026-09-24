import Foundation

/// An error envelope from Herdr: `{"id":..., "error":{"code","message"}}`.
public struct HerdrError: Decodable, Error, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

/// Result of `agent.list`: `{"type":"agent_list","agents":[...]}`.
public struct AgentListResult: Decodable, Equatable, Sendable {
    public let agents: [AgentInfo]

    public init(agents: [AgentInfo]) {
        self.agents = agents
    }
}

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

/// Newline-delimited JSON codec for Herdr's socket protocol.
public enum HerdrProtocol {
    private struct EmptyParams: Encodable {}

    private struct Request<P: Encodable>: Encodable {
        let id: String
        let method: String
        let params: P
    }

    private struct Envelope<R: Decodable>: Decodable {
        let id: String
        let result: R?
        let error: HerdrError?
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

    /// Decodes a response line. Throws `HerdrError` for an error envelope and
    /// `DecodingError` when neither `result` nor `error` is present.
    public static func decodeResult<R: Decodable>(_ line: Data, as type: R.Type) throws -> R {
        let envelope = try JSONDecoder().decode(Envelope<R>.self, from: line)
        if let error = envelope.error { throw error }
        guard let result = envelope.result else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "response has neither result nor error"))
        }
        return result
    }
}
