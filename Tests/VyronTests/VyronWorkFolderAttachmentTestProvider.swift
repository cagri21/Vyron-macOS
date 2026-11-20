import VyronCore

actor VyronWorkFolderAttachmentTestProvider: VyronDevelopmentMessageBudgetProviding {
    private(set) var requests: [[DevelopmentMessage]] = []
    private(set) var requestedModels: [String] = []
    private(set) var requestedEfforts: [AgentEffort] = []

    nonisolated func developmentMessageBudget(for model: String) -> VyronDevelopmentMessageBudget {
        model == "gpt-6.2-sol" ? .init(workingBytes: 98_304, maximumBytes: 131_072) : .standard
    }

    func models() async throws -> [LocalModel] {
        [LocalModel(name: "gpt-6.2-sol", size: 1, capabilities: ["tools"])]
    }

    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard systemPrompt?.contains("Generate suggested follow-up questions") == true else {
            throw ModelProviderError.unsupportedTools
        }
        return #"{"questions":[]}"#
    }

    func developmentModel(
        model: String,
        automaticModelSelection: Bool,
        effort: AgentEffort
    ) async throws -> LocalModel {
        LocalModel(name: model, size: 1, capabilities: ["tools"])
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        requests.append(messages)
        requestedModels.append(model)
        requestedEfforts.append(effort)
        return DevelopmentStep(message: DevelopmentMessage(role: "assistant", content: "Folder comparison complete."))
    }

    // The ModelProvider tool catalog boundary supplies this signature.
    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode,
        externalTools: [DevelopmentExternalTool]
    ) async throws -> DevelopmentStep {
        try await developmentStep(model: model, messages: messages, effort: effort, mode: mode)
    }
}
