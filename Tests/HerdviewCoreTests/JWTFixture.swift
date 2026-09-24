import Foundation

/// An unsigned JWT carrying `claims`, shaped like the access tokens Grok and
/// Codex store. Nothing in Herdview verifies a signature, so none is needed.
func jwt(_ claims: [String: Any]) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: claims)) ?? Data()
    let payload = data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "eyJhbGciOiJub25lIn0.\(payload).sig"
}
