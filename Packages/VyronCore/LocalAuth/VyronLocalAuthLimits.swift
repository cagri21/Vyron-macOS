import Foundation

enum VyronLocalAuthLimits {
    static let endpoint = "http://127.0.0.1:8327"
    static let keychainService = "com.vyron.local-auth"
    static let sessionService = "vyron-local-auth"
    static let schemaVersion = 1
    static let secretBytes = 32
    static let tokenCharacters = 43
    static let responseBytes = 65_536
    static let ciphertextBytes = 32_768
    static let credentialBytes = 16_384
    static let configurationBytes = 4_096
    static let bootstrapBytes = 128
    static let timeout: TimeInterval = 5
    static let maximumConnections = 100
    static let attempts = 2
}
