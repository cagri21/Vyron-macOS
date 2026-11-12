import VyronModelDomain

public enum VyronOpenAIUsageResult: Sendable, Equatable {
    case measured(VyronOpenAITokenUsage)
    case unavailable(VyronOpenAIUsageUnavailable)
}
