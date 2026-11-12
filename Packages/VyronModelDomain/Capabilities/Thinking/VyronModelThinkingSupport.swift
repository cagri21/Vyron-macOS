public enum VyronModelThinkingSupport: Equatable, Sendable {
    case unverified
    case boolean
    case levels(VyronModelThinkingLevels)
    case unsupported
    case providerDefaultOnly
}
