import Foundation
import LocalAuthentication
import Security
import VyronLocalization
import VyronModelDomain

public struct ModelCredentialStore: Sendable {
    private let service: String

    public init(service: String = "com.vyron.model-connections") { self.service = service }

    public func key(for id: UUID) throws -> String {
        var query = baseQuery(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw ModelCredentialError.unavailable
        }
        return key
    }

    public func setKey(_ key: String, for id: UUID) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.utf8.count <= VyronModelCredentialLimits.maximumStoredKeyBytes,
            !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            throw ModelProviderError.invalidSettings(VyronModelDataText.apiKeyTooLong)
        }
        if key.isEmpty { try removeKey(for: id); return }
        let query = baseQuery(id)
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(key.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw ModelCredentialError.unavailable }
        } else if update != errSecSuccess {
            throw ModelCredentialError.unavailable
        }
    }

    public func removeKey(for id: UUID) throws {
        let status = SecItemDelete(baseQuery(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ModelCredentialError.unavailable }
    }

    /// Restore a missing key without overwriting a concurrent edit or another app version's update.
    public func restoreKeyIfMissing(_ requested: String, for id: UUID) throws -> Bool {
        let key = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= VyronModelCredentialLimits.maximumStoredKeyBytes,
            !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            throw ModelProviderError.invalidSettings(VyronModelDataText.apiKeyTooLong)
        }
        var item = baseQuery(id)
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else { throw ModelCredentialError.unavailable }
        return true
    }

    private func baseQuery(_ id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
    }
}
