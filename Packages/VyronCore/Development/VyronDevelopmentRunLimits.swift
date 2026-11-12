enum VyronDevelopmentRunLimits {
    static let checkpointBytes = VyronDevelopmentTaskLimits.defaultContextBytes
    static let toolOutputBytes = VyronDevelopmentMessageBudget.maximumToolOutputBytes
    static let recoveryAttempts = 2
    static let stagnantRounds = 3
}
