import VyronCore

struct VyronContinuationModelSelection: Equatable, Sendable {
    let model: String
    let automaticModelSelection: Bool
    let effort: AgentEffort
}
