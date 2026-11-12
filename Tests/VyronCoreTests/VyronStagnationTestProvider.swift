@testable import VyronCore

actor VyronStagnationTestProvider: ModelProvider {
    private let step: @Sendable (Int, [DevelopmentMessage]) async throws -> DevelopmentMessage
    private let summary: @Sendable ([ChatMessage], String?) async throws -> String
    private var requests: [[DevelopmentMessage]] = []
    private var summaries: [VyronStagnationTestSummaryRequest] = []

    init(
        step: @escaping @Sendable (Int, [DevelopmentMessage]) async throws -> DevelopmentMessage,
        summary: @escaping @Sendable ([ChatMessage], String?) async throws -> String
    ) {
        self.step = step
        self.summary = summary
    }

    func recordedRequests() -> [[DevelopmentMessage]] { requests }
    func recordedSummaries() -> [VyronStagnationTestSummaryRequest] { summaries }

    func models() async throws -> [LocalModel] {
        [LocalModel(name: "fixture-coder", size: 1)]
    }

    // These signatures conform to the existing provider boundary.
    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        summaries.append(VyronStagnationTestSummaryRequest(
            model: model, messages: messages, systemPrompt: systemPrompt
        ))
        let response = try await summary(messages, systemPrompt)
        onToken(response)
        return response
    }

    func developmentModel(
        model: String,
        automaticModelSelection: Bool,
        effort: AgentEffort
    ) async throws -> LocalModel {
        LocalModel(name: "fixture-coder", size: 1, capabilities: ["tools"])
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        requests.append(messages)
        let reply = try await step(requests.count, messages)
        return DevelopmentStep(message: reply)
    }

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
