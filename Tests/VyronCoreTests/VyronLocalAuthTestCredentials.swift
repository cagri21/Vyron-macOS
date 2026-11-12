import Foundation
@testable import VyronCore

actor VyronLocalAuthTestCredentials: VyronLocalAuthCredentialStoring {
    private var primary: [UUID: String] = [:]
    private var secrets: [VyronLocalAuthSecretAccount: Data] = [:]
    private var failure: VyronLocalAuthError?
    private(set) var primaryReads = 0
    private(set) var secretReads = 0
    private(set) var secretWrites = 0

    func modelKey(for connectionID: UUID) async throws -> String {
        primaryReads += 1
        if let failure { throw failure }
        return primary[connectionID] ?? ""
    }

    func deviceSecret(for account: VyronLocalAuthSecretAccount) async throws -> Data? {
        secretReads += 1
        if let failure { throw failure }
        return secrets[account]
    }

    func storeDeviceSecretIfMissing(_ value: Data, for account: VyronLocalAuthSecretAccount) async throws -> Data {
        secretWrites += 1
        if let failure { throw failure }
        if let current = secrets[account] { return current }
        secrets[account] = value
        return value
    }

    func setPrimary(_ key: String, for id: UUID) { primary[id] = key }
    func setSecret(_ value: Data?, account: VyronLocalAuthSecretAccount) { secrets[account] = value }
    func fail(with error: VyronLocalAuthError?) { failure = error }
}
