import VyronModelDomain

public struct VyronOpenAITokenUsage: Sendable, Equatable {
    public let inputTokens: Int
    /// Includes reasoning tokens. Do not charge reasoning a second time.
    public let outputTokens: Int
    public let inputDetails: VyronOpenAIInputTokenUsage

    public init(inputTokens: Int, outputTokens: Int, inputDetails: VyronOpenAIInputTokenUsage) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.inputDetails = inputDetails
    }
}
