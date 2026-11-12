import VyronCore

struct VyronSideChatConfiguration: Sendable {
    let provider: any ModelProvider
    let model: String
    let connection: VyronSideChatConnection
    let effort: AgentEffort

    init(
        provider: any ModelProvider,
        model: String,
        connection: VyronSideChatConnection,
        effort: AgentEffort = .automatic
    ) {
        self.provider = provider
        self.model = model
        self.connection = connection
        self.effort = effort
    }
}
