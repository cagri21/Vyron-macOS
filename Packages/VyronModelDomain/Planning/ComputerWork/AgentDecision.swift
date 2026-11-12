import Foundation

public struct AgentDecision: Sendable, Equatable {
    public let proposal: ControlProposal
    public let effort: AgentEffort
    public let budget: AgentBudget
    public let model: String

    public init(proposal: ControlProposal, effort: AgentEffort, budget: AgentBudget, model: String) {
        self.proposal = proposal
        self.effort = effort
        self.budget = budget
        self.model = model
    }
}
