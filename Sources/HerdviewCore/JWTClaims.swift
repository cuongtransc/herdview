import Foundation

/// The two claims Herdview reads from an access token that is a JWT. The
/// signature is not checked: the token only ever goes back to its issuer,
/// which checks it. Anything that is not a readable JWT has no claims.
enum JWTClaims {
    static func subject(of token: String) -> String? {
        guard let subject = payload(of: token)?["sub"] as? String, !subject.isEmpty else { return nil }
        return subject
    }

    static func expiry(of token: String) -> Date? {
        guard let seconds = payload(of: token)?["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: seconds.doubleValue)
    }

    private static func payload(of token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
