import XCTest
@testable import HerdviewCore

final class JWTClaimsTests: XCTestCase {
    func testReadsSubjectAndExpiry() {
        let token = jwt(["sub": "user-1", "exp": 1_790_261_909])
        XCTAssertEqual(JWTClaims.subject(of: token), "user-1")
        XCTAssertEqual(JWTClaims.expiry(of: token), Date(timeIntervalSince1970: 1_790_261_909))
    }

    /// Base64url payloads drop their padding; every length must still decode.
    func testDecodesPayloadsOfEveryPaddingLength() {
        for sub in ["a", "ab", "abc", "abcd"] {
            XCTAssertEqual(JWTClaims.subject(of: jwt(["sub": sub])), sub)
        }
    }

    func testAnythingElseHasNoClaims() {
        for token in ["", "sk-opencode-go-key", "a.b", "a.!!!.c", "a.b.c.d", jwt(["sub": ""]), jwt(["exp": "soon"])] {
            XCTAssertNil(JWTClaims.subject(of: token), token)
            XCTAssertNil(JWTClaims.expiry(of: token), token)
        }
    }
}
