import CryptoKit
import Foundation

/// Which Account an entry belongs to: its Provider and the identity its
/// credential carries. The id is never shown or logged.
public struct QuotaAccountKey: Hashable, Sendable {
    public let provider: QuotaProvider
    public let id: String

    public init(provider: QuotaProvider, id: String) {
        self.provider = provider
        self.id = id
    }
}

/// One sign-in to a Provider, and every Source on this Mac that holds it.
public struct QuotaAccount: Equatable, Sendable {
    public let key: QuotaAccountKey
    public let sources: [QuotaSource]

    public var provider: QuotaProvider { key.provider }

    public init(key: QuotaAccountKey, sources: [QuotaSource]) {
        self.key = key
        self.sources = sources
    }
}

/// Turns the credentials read from every Source into Accounts. Quota belongs
/// to an Account, so two Sources holding one Account ask once, and two
/// Accounts of one Provider each get a row (ADR 0006).
public enum QuotaAccounts {
    /// The account id the credential carries, else its JWT subject, else a
    /// SHA-256 of the token: an API key has no identity but itself, and the
    /// hash keeps the key out of every place the id goes.
    public static func identity(of credential: QuotaCredential) -> String {
        if let account = credential.accountId { return account }
        if let subject = JWTClaims.subject(of: credential.token) { return subject }
        return SHA256.hash(data: Data(credential.token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// `found` in Source order. Accounts come out in the order their first
    /// Source was read, so rows keep their places between polls. Within an
    /// Account the credential that expires last is used: a tool still running
    /// keeps the numbers fresh after another has gone quiet.
    public static func group(_ found: [(source: QuotaSource, credential: QuotaCredential)],
                             provider: QuotaProvider) -> [(account: QuotaAccount, credential: QuotaCredential)] {
        var order: [String] = []
        var sources: [String: [QuotaSource]] = [:]
        var chosen: [String: QuotaCredential] = [:]
        for (source, credential) in found {
            let id = identity(of: credential)
            guard let current = chosen[id] else {
                order.append(id)
                sources[id] = [source]
                chosen[id] = credential
                continue
            }
            if !sources[id, default: []].contains(source) { sources[id, default: []].append(source) }
            if outlasts(credential, current) { chosen[id] = credential }
        }
        return order.compactMap { id in
            guard let credential = chosen[id] else { return nil }
            let account = QuotaAccount(key: QuotaAccountKey(provider: provider, id: id), sources: sources[id, default: []])
            return (account: account, credential: credential)
        }
    }

    /// Whether `candidate` expires strictly after `current`. A token with no
    /// readable expiry never beats one with, and a tie keeps the earlier Source.
    static func outlasts(_ candidate: QuotaCredential, _ current: QuotaCredential) -> Bool {
        guard let new = JWTClaims.expiry(of: candidate.token) else { return false }
        guard let old = JWTClaims.expiry(of: current.token) else { return true }
        return new > old
    }
}
