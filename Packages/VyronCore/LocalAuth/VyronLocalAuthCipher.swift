import CryptoKit
import Foundation

enum VyronLocalAuthCipher {
    static func newKey() -> Data { SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) } }

    static func encrypt(_ value: String, connectionID: UUID, key: Data) throws -> String {
        try validate(value)
        guard key.count == VyronLocalAuthLimits.secretBytes else { throw VyronLocalAuthError.credentialsUnavailable }
        do {
            let sealed = try AES.GCM.seal(
                Data(value.utf8), using: SymmetricKey(data: key), authenticating: additionalData(connectionID)
            )
            guard let combined = sealed.combined, combined.count <= VyronLocalAuthLimits.ciphertextBytes else {
                throw VyronLocalAuthError.integrityFailed
            }
            return combined.base64EncodedString()
        } catch { throw VyronLocalAuthError.integrityFailed }
    }

    static func decrypt(_ payload: String, connectionID: UUID, key: Data) throws -> String {
        guard key.count == VyronLocalAuthLimits.secretBytes,
            let data = Data(base64Encoded: payload), data.count >= 28,
            data.count <= VyronLocalAuthLimits.ciphertextBytes else { throw VyronLocalAuthError.integrityFailed }
        do {
            let sealed = try AES.GCM.SealedBox(combined: data)
            let plaintext = try AES.GCM.open(
                sealed, using: SymmetricKey(data: key), authenticating: additionalData(connectionID)
            )
            guard let value = String(data: plaintext, encoding: .utf8) else { throw VyronLocalAuthError.integrityFailed }
            try validate(value)
            return value
        } catch { throw VyronLocalAuthError.integrityFailed }
    }

    private static func additionalData(_ connectionID: UUID) -> Data {
        Data("vyron.credential.v1:\(connectionID.uuidString.lowercased())".utf8)
    }

    private static func validate(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            value.utf8.count <= VyronLocalAuthLimits.credentialBytes,
            !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw VyronLocalAuthError.integrityFailed
        }
    }
}
