import Foundation

/// What a Provider's usage endpoint needs to answer for this account.
public struct QuotaCredential: Equatable, Sendable {
    public let token: String
    /// Codex's `ChatGPT-Account-Id` and Grok's `x-userid`; unused otherwise.
    public let accountId: String?

    public init(token: String, accountId: String? = nil) {
        self.token = token
        self.accountId = accountId
    }
}

/// Reads the credential each CLI already stores. Read-only: Herdview never
/// refreshes or writes one back (ADR 0005). `nil` means not signed in.
public enum QuotaCredentials {
    /// Where `source` keeps its credentials, or `nil` for Claude, whose
    /// credential is in the Keychain.
    public static func filePath(for source: QuotaSource, home: String) -> String? {
        switch source {
        case .claude: return nil
        case .codex: return home + "/.codex/auth.json"
        case .opencode: return home + "/.local/share/opencode/auth.json"
        case .grok: return home + "/.grok/auth.json"
        case .pi: return home + "/.pi/agent/auth.json"
        }
    }

    /// The Keychain item Claude Code keeps its sign-in in.
    public static let claudeKeychainService = "Claude Code-credentials"

    public static func parse(_ provider: QuotaProvider, _ data: Data) -> QuotaCredential? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        switch provider {
        case .claude:
            let oauth = json["claudeAiOauth"] as? [String: Any]
            return credential(token: oauth?["accessToken"], accountId: nil)
        case .codex:
            let tokens = json["tokens"] as? [String: Any]
            return credential(token: tokens?["access_token"], accountId: tokens?["account_id"])
        case .opencodeGo:
            let entry = json["opencode-go"] as? [String: Any]
            return credential(token: entry?["key"], accountId: nil)
        case .grok:
            return grok(json)
        }
    }

    /// The credential `source` holds for `provider`. Every Source but pi is a
    /// Provider's own CLI and keeps the format `parse(_:_:)` reads; pi keeps
    /// several Providers in one file, each under its own key and type.
    public static func parse(_ provider: QuotaProvider, from source: QuotaSource, _ data: Data) -> QuotaCredential? {
        guard source == .pi else { return parse(provider, data) }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        switch provider {
        case .opencodeGo:
            guard let entry = json["opencode-go"] as? [String: Any],
                  entry["type"] as? String == "api_key" else { return nil }
            return credential(token: entry["key"], accountId: nil)
        case .grok:
            // pi keeps no user id. The token's subject is the id Grok's CLI
            // stores, and the billing endpoint wants it as `x-userid`.
            guard let entry = json["xai"] as? [String: Any],
                  entry["type"] as? String == "oauth",
                  let token = entry["access"] as? String else { return nil }
            return credential(token: token, accountId: JWTClaims.subject(of: token))
        case .claude, .codex:
            return nil
        }
    }

    /// Grok keys its file by issuer. xAI's own issuer wins, with or without a
    /// `::<id>` suffix; any other issuer is used only when xAI's is absent.
    /// Keys are sorted so the choice among several never depends on
    /// dictionary order.
    private static func grok(_ json: [String: Any]) -> QuotaCredential? {
        let issuer = "https://auth.x.ai"
        let keys = json.keys.sorted()
        let preferred = keys.filter { $0 == issuer || $0.hasPrefix(issuer + "::") }
        for key in preferred + keys.filter({ !preferred.contains($0) }) {
            let entry = json[key] as? [String: Any]
            if let found = credential(token: entry?["key"], accountId: entry?["user_id"]) {
                return found
            }
        }
        return nil
    }

    private static func credential(token: Any?, accountId: Any?) -> QuotaCredential? {
        guard let token = token as? String, !token.isEmpty else { return nil }
        let account = (accountId as? String).flatMap { $0.isEmpty ? nil : $0 }
        return QuotaCredential(token: token, accountId: account)
    }
}
