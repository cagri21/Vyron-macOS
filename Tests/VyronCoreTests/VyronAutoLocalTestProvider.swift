import Foundation
import VyronModelDomain

actor VyronAutoLocalTestProvider: VyronEffortChatProviding {
    private let reply: @Sendable (VyronChatInferenceRequest, Int) async throws -> String
    private let emittedTokens: [String]
    private var requests: [VyronChatInferenceRequest] = []
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []

    init(response: String, emittedTokens: [String] = []) {
        reply = { _, _ in response }
        self.emittedTokens = emittedTokens
    }

    init(reply: @escaping @Sendable (VyronChatInferenceRequest, Int) async throws -> String) {
        self.reply = reply
        emittedTokens = []
    }

    func recordedRequests() -> [VyronChatInferenceRequest] { requests }

    func waitUntilRequested() async {
        guard requests.isEmpty else { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func models() async throws -> [LocalModel] { [] }

    // Preserve the stable provider protocol's boundary signatures.
    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await chat(
            VyronChatInferenceRequest(
                model: model, messages: messages,
                configuration: VyronChatInferenceConfiguration(systemPrompt: systemPrompt, effort: .automatic)
            ),
            onToken: onToken
        )
    }

    func chat(
        _ request: VyronChatInferenceRequest,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        requests.append(request)
        let waiters = startedWaiters
        startedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        emittedTokens.forEach(onToken)
        return try await reply(request, requests.count)
    }

    func developmentModel(
        model: String,
        automaticModelSelection: Bool,
        effort: AgentEffort
    ) async throws -> LocalModel {
        throw ModelProviderError.unsupportedTools
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        throw ModelProviderError.unsupportedTools
    }
}
