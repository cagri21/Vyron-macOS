import Foundation

enum VyronOllamaNativeToolCheckPolicy {
    static let toolName = "vyron_check_tools"
    static let contextTokens = 8_192
    static let maximumOutputTokens = 2_048
    static let minimumOutputTokens = 128
    static let outputContextDivisor = 4
    static let timeoutSeconds: TimeInterval = 120
    static let maximumResponseBytes = 65_536
    static let maximumCachedProofs = 64
}
