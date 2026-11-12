import VyronModelDomain

public enum VyronOpenAIUsageUnavailable: Sendable, Equatable {
    case missingUsage
    case invalidUsage
    case interrupted
    case unsupportedModality
}
