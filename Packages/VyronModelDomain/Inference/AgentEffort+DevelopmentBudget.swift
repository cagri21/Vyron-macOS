extension AgentEffort {
    public var developmentBudget: VyronDevelopmentEffortBudget {
        switch self {
        case .quick: .init(maximumToolRounds: 12, outputTokens: 2_048)
        case .automatic, .balanced: .init(maximumToolRounds: 20, outputTokens: 4_096)
        case .deep: .init(maximumToolRounds: 30, outputTokens: 6_144)
        case .extraHigh: .init(maximumToolRounds: 30, outputTokens: 8_192)
        case .maximum: .init(maximumToolRounds: 30, outputTokens: 10_240)
        case .ultra: .init(maximumToolRounds: 30, outputTokens: 12_288)
        }
    }

    var prioritizesModelQuality: Bool {
        switch self {
        case .deep, .extraHigh, .maximum, .ultra: true
        case .automatic, .quick, .balanced: false
        }
    }
}
