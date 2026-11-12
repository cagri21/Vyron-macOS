import VyronCore

struct VyronConversationInferenceSelection {
    let provider: any ModelProvider
    let model: String
    let effort: AgentEffort

    func routingChat(using candidates: [LocalModel]?) throws -> Self {
        guard let candidates else { return self }
        let routingEffort: AgentEffort = effort == .automatic ? .balanced : effort
        guard let automatic = AgentModelRouter.selectModel(
            from: candidates,
            preferredModel: model,
            effort: routingEffort
        ) else { throw VyronAutomaticModelSelectionError() }
        return Self(provider: provider, model: automatic.name, effort: effort)
    }
}
