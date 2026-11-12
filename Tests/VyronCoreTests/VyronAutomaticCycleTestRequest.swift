import VyronCore

struct VyronAutomaticCycleTestRequest: Sendable {
    let model: String
    let messages: [DevelopmentMessage]
    let effort: AgentEffort
    let mode: DevelopmentMode
}
