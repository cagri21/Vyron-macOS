import Foundation

public enum VyronLocalAuthSecretAccount: String, Sendable, Hashable {
    case deviceToken = "device-token"
    case encryptionKey = "encryption-key"
}
