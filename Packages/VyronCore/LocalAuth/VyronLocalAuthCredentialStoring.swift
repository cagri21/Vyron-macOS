import Foundation

public protocol VyronLocalAuthCredentialStoring: Sendable {
    func modelKey(for connectionID: UUID) async throws -> String
    func deviceSecret(for account: VyronLocalAuthSecretAccount) async throws -> Data?
    func storeDeviceSecretIfMissing(_ value: Data, for account: VyronLocalAuthSecretAccount) async throws -> Data
}
