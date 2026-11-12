import VyronCore

actor VyronMacWorkRoutingTestProvider: ModelProvider {
    private(set) var toolNames: Set<String> = []
    private(set) var requestedModels: [String] = []

    func models() async throws -> [LocalModel] { [] }

    // Preserve ModelProvider's existing transport signatures at this test boundary.
    func chat(
        model: String, messages: [ChatMessage], systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        "{\"questions\":[]}"
    }

    func developmentModel(
        model: String, automaticModelSelection: Bool, effort: AgentEffort
    ) async throws -> LocalModel {
        LocalModel(name: model, size: 1, capabilities: ["tools"])
    }

    func developmentStep(
        model: String, messages: [DevelopmentMessage], effort: AgentEffort, mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        try await developmentStep(model: model, messages: messages, effort: effort, mode: mode, externalTools: [])
    }

    func developmentStep(
        model: String, messages: [DevelopmentMessage], effort: AgentEffort,
        mode: DevelopmentMode, externalTools: [DevelopmentExternalTool]
    ) async throws -> DevelopmentStep {
        requestedModels.append(model)
        toolNames = Set(externalTools.map(\.name))
        return DevelopmentStep(message: DevelopmentMessage(
            role: "assistant", content: "Native app tools are available."
        ))
    }
}
