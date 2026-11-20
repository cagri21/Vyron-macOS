import VyronModelDomain

actor VyronAdaptiveBudgetTestProvider: VyronDevelopmentAdaptiveBudgetProviding {
    private let budget: @Sendable (VyronDevelopmentBudgetRequest) async throws -> VyronDevelopmentMessageBudget
    private let step: @Sendable (Int, [DevelopmentMessage]) async throws -> DevelopmentMessage
    private(set) var requests: [VyronDevelopmentBudgetRequest] = []
    private(set) var inferenceCount = 0

    init(
        budget: @escaping @Sendable (VyronDevelopmentBudgetRequest) async throws -> VyronDevelopmentMessageBudget,
        step: @escaping @Sendable (Int, [DevelopmentMessage]) async throws -> DevelopmentMessage = { _, _ in
            DevelopmentMessage(role: "assistant", content: "Read-only review complete.")
        }
    ) {
        self.budget = budget
        self.step = step
    }

    func developmentBudget(for request: VyronDevelopmentBudgetRequest) async throws -> VyronDevelopmentMessageBudget {
        requests.append(request)
        return try await budget(request)
    }

    func models() async throws -> [LocalModel] { [] }

    func developmentModel(
        model: String, automaticModelSelection: Bool, effort: AgentEffort
    ) async throws -> LocalModel {
        LocalModel(name: "selected-coder", size: 1, capabilities: ["tools"])
    }

    // Established provider signatures are kept intact at this test boundary.
    func chat(
        model: String, messages: [ChatMessage], systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String { throw ModelProviderError.unsupportedTools }

    func developmentStep(
        model: String, messages: [DevelopmentMessage], effort: AgentEffort, mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        inferenceCount += 1
        let reply = try await step(inferenceCount, messages)
        return DevelopmentStep(message: reply)
    }

    func developmentStep(
        model: String, messages: [DevelopmentMessage], effort: AgentEffort, mode: DevelopmentMode,
        externalTools: [DevelopmentExternalTool]
    ) async throws -> DevelopmentStep {
        try await developmentStep(model: model, messages: messages, effort: effort, mode: mode)
    }
}
