import Foundation

struct VyronLocalAuthCredentialRecord: Codable {
    let revision: Int
    let encryptedPayload: String?

    func validate() throws {
        guard revision >= 0 else { throw VyronLocalAuthError.invalidResponse }
        if let encryptedPayload {
            guard revision > 0, let payload = Data(base64Encoded: encryptedPayload), payload.count >= 28,
                payload.count <= VyronLocalAuthLimits.ciphertextBytes,
                payload.base64EncodedString() == encryptedPayload else { throw VyronLocalAuthError.invalidResponse }
        }
    }
}
