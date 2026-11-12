import Foundation
import LocalAuthentication
import Security
import VyronModelData

public struct VyronLocalAuthKeychainCredentials: VyronLocalAuthCredentialStoring {
    private let modelCredentials: ModelCredentialStore

    public init(modelCredentials: ModelCredentialStore = ModelCredentialStore()) {
        self.modelCredentials = modelCredentials
    }

    public func modelKey(for connectionID: UUID) async throws -> String {
        try Task.checkCancellation()
        do { return try modelCredentials.key(for: connectionID) }
        catch { throw VyronLocalAuthError.credentialsUnavailable }
    }

    public func deviceSecret(for account: VyronLocalAuthSecretAccount) async throws -> Data? {
        try Task.checkCancellation()
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let value = result as? Data else {
            throw VyronLocalAuthError.credentialsUnavailable
        }
        return value
    }

    public func storeDeviceSecretIfMissing(_ value: Data, for account: VyronLocalAuthSecretAccount) async throws -> Data {
        try Task.checkCancellation()
        guard value.count == VyronLocalAuthLimits.secretBytes else { throw VyronLocalAuthError.credentialsUnavailable }
        var item = baseQuery(account)
        item[kSecValueData as String] = value
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            guard let existing = try await deviceSecret(for: account) else {
                throw VyronLocalAuthError.credentialsUnavailable
            }
            return existing
        }
        guard status == errSecSuccess else { throw VyronLocalAuthError.credentialsUnavailable }
        return value
    }

    private func baseQuery(_ account: VyronLocalAuthSecretAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: VyronLocalAuthLimits.keychainService,
            kSecAttrAccount as String: account.rawValue
        ]
    }
}
