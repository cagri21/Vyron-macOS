@testable import VyronCore

actor VyronStagnationSummaryTestProvider: ModelProvider, VyronEffortChatProviding {
    private let reply: @Sendable () async throws -> String
    private var requests: [VyronChatInferenceRequest] = []
    private var developmentCalls = 0

    init(reply: @escaping @Sendable () async throws -> String) {
        self.reply = reply
    }

    func recordedRequests() -> [VyronChatInferenceRequest] { requests }
    func recordedDevelopmentCalls() -> Int { developmentCalls }

    func models() async throws -> [LocalModel] { [] }

    // These signatures implement the established provider boundary.
    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        throw ModelProviderError.unsupportedTools
    }

    func chat(
        _ request: VyronChatInferenceRequest,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        requests.append(request)
        return try await reply()
    }

    func developmentModel(
        model: String,
        automaticModelSelection: Bool,
        effort: AgentEffort
    ) async throws -> LocalModel {
        throw ModelProviderError.invalidModel
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        developmentCalls += 1
        throw ModelProviderError.unsupportedTools
    }
}
