/// Output allowance varies independently of the existing bounded execution limit.
public struct VyronDevelopmentEffortBudget: Equatable, Sendable {
    public let maximumToolRounds: Int
    public let outputTokens: Int

    public init(maximumToolRounds: Int, outputTokens: Int) {
        self.maximumToolRounds = maximumToolRounds
        self.outputTokens = outputTokens
    }
}
