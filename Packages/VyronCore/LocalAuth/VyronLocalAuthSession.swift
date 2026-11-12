import Foundation

struct VyronLocalAuthSession: Decodable {
    let service: String
    let schemaVersion: Int
    let instanceId: UUID
    let hasEncryptedCredentials: Bool

    func validate() throws {
        guard service == VyronLocalAuthLimits.sessionService, schemaVersion == VyronLocalAuthLimits.schemaVersion else {
            throw VyronLocalAuthError.invalidResponse
        }
    }
}
