import VyronCore
import VyronModelDomain

actor VyronAutoLocalAppTestProvider: ModelProvider, VyronEffortChatProviding {
    private(set) var chatModels: [String] = []
    private(set) var efforts: [AgentEffort] = []
    private(set) var developmentModels: [String] = []
    private(set) var developmentRequests: [[DevelopmentMessage]] = []
    private(set) var developmentModes: [DevelopmentMode] = []
    private(set) var externalToolNames: [[String]] = []
    private(set) var automaticSelections: [Bool] = []

    func models() async throws -> [LocalModel] { [] }

    // ModelProvider and VyronEffortChatProviding define these transport signatures.
    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        if systemPrompt?.contains("Generate suggested follow-up questions") == true { return "{\"questions\":[]}" }
        chatModels.append(model)
        onToken("Auto Local answer")
        return "Auto Local answer"
    }

    func chat(
        _ request: VyronChatInferenceRequest,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        efforts.append(request.configuration.effort)
        return try await chat(
            model: request.model, messages: request.messages,
            systemPrompt: request.configuration.systemPrompt, onToken: onToken
        )
    }

    func developmentModel(
        model: String,
        automaticModelSelection: Bool,
        effort: AgentEffort
    ) async throws -> LocalModel {
        automaticSelections.append(automaticModelSelection)
        return LocalModel(name: model, size: 1, capabilities: ["tools"])
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        try await developmentStep(model: model, messages: messages, effort: effort, mode: mode, externalTools: [])
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode,
        externalTools: [DevelopmentExternalTool]
    ) async throws -> DevelopmentStep {
        developmentModels.append(model)
        developmentRequests.append(messages)
        developmentModes.append(mode)
        externalToolNames.append(externalTools.map(\.name))
        efforts.append(effort)
        return DevelopmentStep(message: DevelopmentMessage(role: "assistant", content: "Auto Local work answer"))
    }
}
