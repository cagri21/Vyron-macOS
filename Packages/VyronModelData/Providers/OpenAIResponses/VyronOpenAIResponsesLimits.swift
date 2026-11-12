import Foundation
import VyronModelDomain

enum VyronOpenAIResponsesLimits {
    static let continuationSource = "openai.responses.v1"
    static let responseBytes = 2_097_152
    static let eventBytes = 2_097_152
    static let requestBytes = 25_165_824
    static let argumentBytes = 64_000
    static let identifierBytes = 512
    static let functionNamePattern = "^[a-zA-Z0-9_-]{1,64}$"
    static let maximumCalls = 4
    static let requestTimeout: TimeInterval = 180
    static let contextOverhead = 2_048
    static let minimumDevelopmentOutput = 512
    static let tokenCountResponseBytes = 4_096
}
