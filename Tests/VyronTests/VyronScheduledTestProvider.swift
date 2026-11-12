import Foundation
@testable import VyronCore

actor VyronScheduledTestProvider: ModelProvider {
    private(set) var requests: [VyronScheduledProviderChatRequest] = []
    private var pending: [CheckedContinuation<String, Error>] = []

    func models() async throws -> [LocalModel] {
        [LocalModel(name: "saved-model", size: 1)]
    }

    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        requests.append(VyronScheduledProviderChatRequest(
            model: model,
            messages: messages,
            systemPrompt: systemPrompt
        ))
        let response = try await withCheckedThrowingContinuation { pending.append($0) }
        onToken(response)
        return response
    }

    func developmentModel(
        model: String,
        automaticModelSelection: Bool,
        effort: AgentEffort
    ) async throws -> LocalModel {
        LocalModel(name: model, size: 1)
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        throw ModelProviderError.unsupportedTools
    }

    func complete(_ response: String) {
        precondition(!pending.isEmpty)
        pending.removeFirst().resume(returning: response)
    }

    func fail() {
        precondition(!pending.isEmpty)
        pending.removeFirst().resume(throwing: ModelProviderError.connectionFailed)
    }

    func cancelOutstanding() {
        let outstanding = pending
        pending.removeAll()
        for continuation in outstanding {
            continuation.resume(throwing: CancellationError())
        }
    }
}
