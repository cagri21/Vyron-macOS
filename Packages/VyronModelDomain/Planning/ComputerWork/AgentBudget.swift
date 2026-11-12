import Foundation

public struct AgentBudget: Codable, Sendable, Equatable {
    public let contextTokens: Int
    public let outputTokens: Int
    public let snapshotBytes: Int
    public let historyBytes: Int
    public let maxSteps: Int

    public init(contextTokens: Int, outputTokens: Int, snapshotBytes: Int, historyBytes: Int, maxSteps: Int) {
        self.contextTokens = contextTokens
        self.outputTokens = outputTokens
        self.snapshotBytes = snapshotBytes
        self.historyBytes = historyBytes
        self.maxSteps = maxSteps
    }

    public static func forEffort(_ effort: AgentEffort) -> AgentBudget {
        switch effort {
        case .quick:
            AgentBudget(
                contextTokens: 16_384,
                outputTokens: 384,
                snapshotBytes: 4_000,
                historyBytes: 1_024,
                maxSteps: 6
            )
        case .automatic, .balanced:
            AgentBudget(
                contextTokens: 32_768,
                outputTokens: 768,
                snapshotBytes: 8_000,
                historyBytes: 2_048,
                maxSteps: 12
            )
        case .deep:
            AgentBudget(
                contextTokens: 32_768,
                outputTokens: 1_536,
                snapshotBytes: 12_000,
                historyBytes: 4_096,
                maxSteps: 20
            )
        case .extraHigh:
            AgentBudget(
                contextTokens: 32_768,
                outputTokens: 2_048,
                snapshotBytes: 14_000,
                historyBytes: 4_096,
                maxSteps: 20
            )
        case .maximum:
            AgentBudget(
                contextTokens: 32_768,
                outputTokens: 2_560,
                snapshotBytes: 16_000,
                historyBytes: 4_096,
                maxSteps: 20
            )
        case .ultra:
            AgentBudget(
                contextTokens: 32_768,
                outputTokens: 3_072,
                snapshotBytes: 18_000,
                historyBytes: 4_096,
                maxSteps: 20
            )
        }
    }

    package func fitting(baseInputBytes: Int) throws -> AgentBudget {
        // UTF-8 bytes conservatively bound token usage, including scripts with little token compression.
        let context =
            baseInputBytes + snapshotBytes + historyBytes + outputTokens + 2_048 > contextTokens
            ? 32_768 : contextTokens
        let remaining = context - outputTokens - 2_048 - baseInputBytes
        guard remaining >= 0 else { throw AgentPlanningError.inputTooLarge }
        let history = min(historyBytes, remaining / 4)
        let snapshot = min(snapshotBytes, remaining - history)
        return AgentBudget(
            contextTokens: context,
            outputTokens: outputTokens,
            snapshotBytes: snapshot,
            historyBytes: history,
            maxSteps: maxSteps
        )
    }
}
