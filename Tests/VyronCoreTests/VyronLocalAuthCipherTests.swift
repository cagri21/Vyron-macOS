import Foundation
import XCTest
@testable import VyronCore

final class VyronLocalAuthCipherTests: XCTestCase {
    func testAESAuthenticatesCiphertextConnectionIdentityAndKeyWithoutExposingPlaintext() throws {
        let id = UUID()
        let key = VyronLocalAuthCipher.newKey()
        let value = "offline-test-api-key"
        let first = try VyronLocalAuthCipher.encrypt(value, connectionID: id, key: key)
        let second = try VyronLocalAuthCipher.encrypt(value, connectionID: id, key: key)
        XCTAssertNotEqual(first, second, "Each backup uses a fresh GCM nonce.")
        XCTAssertFalse(first.contains(value))
        XCTAssertEqual(try VyronLocalAuthCipher.decrypt(first, connectionID: id, key: key), value)
        XCTAssertThrowsError(try VyronLocalAuthCipher.decrypt(first, connectionID: UUID(), key: key))
        XCTAssertThrowsError(try VyronLocalAuthCipher.decrypt(first, connectionID: id, key: VyronLocalAuthCipher.newKey()))
        var altered = try XCTUnwrap(Data(base64Encoded: first))
        altered[altered.count - 1] ^= 1
        XCTAssertThrowsError(try VyronLocalAuthCipher.decrypt(altered.base64EncodedString(), connectionID: id, key: key))
        XCTAssertThrowsError(try VyronLocalAuthCipher.decrypt("invalid", connectionID: id, key: key))
        XCTAssertFalse(VyronLocalCredentialRestoration(connectionID: id, key: value).description.contains(value))
    }

    func testBootstrapTokenRequiresCanonical32ByteBase64URL() throws {
        let token = Data(repeating: 250, count: 32)
        let text = VyronLocalAuthToken.encode(token)
        XCTAssertEqual(text.utf8.count, 43)
        XCTAssertEqual(try VyronLocalAuthToken.decode(Data((text + "\n").utf8)), token)
        for invalid in ["", text + "=", text + "/", String(text.dropLast()), String(repeating: "!", count: 43)] {
            XCTAssertThrowsError(try VyronLocalAuthToken.decode(Data(invalid.utf8)))
        }
    }
}
