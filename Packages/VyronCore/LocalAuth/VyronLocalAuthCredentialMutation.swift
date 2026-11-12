import Foundation

struct VyronLocalAuthCredentialMutation: Encodable {
    let expectedRevision: Int
    let encryptedPayload: String?

    init(expectedRevision: Int, encryptedPayload: String? = nil) {
        self.expectedRevision = expectedRevision
        self.encryptedPayload = encryptedPayload
    }
}
