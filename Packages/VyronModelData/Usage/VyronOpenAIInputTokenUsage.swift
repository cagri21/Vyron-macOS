import VyronModelDomain

public struct VyronOpenAIInputTokenUsage: Sendable, Equatable {
    public let cachedTokens: Int
    public let cacheWrite30mTokens: Int
    public let cacheWrite12hTokens: Int

    public init(cachedTokens: Int, cacheWrite30mTokens: Int, cacheWrite12hTokens: Int) {
        self.cachedTokens = cachedTokens
        self.cacheWrite30mTokens = cacheWrite30mTokens
        self.cacheWrite12hTokens = cacheWrite12hTokens
    }
}
