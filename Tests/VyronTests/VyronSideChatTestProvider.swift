import Foundation
@testable import VyronCore

actor VyronSideChatTestProvider: ModelProvider, VyronEffortChatProviding {
    private(set) var requests: [VyronSideChatTestRequest] = []
    private(set) var effortRequests: [VyronChatInferenceRequest] = []
    private var continuations: [Int: CheckedContinuation<String, any Error>] = [:]
    private var callbacks: [Int: @Sendable (String) -> Void] = [:]

    func models() async throws -> [LocalModel] { [] }

    func chat(
        _ request: VyronChatInferenceRequest,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        effortRequests.append(request)
        return try await chat(
            model: request.model, messages: request.messages,
            systemPrompt: request.configuration.systemPrompt, onToken: onToken
        )
    }

    // ModelProvider owns these transport signatures.
    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        if systemPrompt?.contains("Generate suggested follow-up questions") == true {
            return #"{"questions":[]}"#
        }
        requests.append(VyronSideChatTestRequest(model: model, messages: messages, systemPrompt: systemPrompt))
        let request = requests.count
        callbacks[request] = onToken
        // Deliberately ignore cancellation until the test releases the request.
        // This verifies that a stale provider cannot modify a stopped or newer turn.
        return try await withCheckedThrowingContinuation { continuations[request] = $0 }
    }

    func emit(_ token: String, request: Int) { callbacks[request]?(token) }

    func complete(_ request: Int, answer: String) {
        continuations.removeValue(forKey: request)?.resume(returning: answer)
        callbacks.removeValue(forKey: request)
    }

    func fail(_ request: Int) {
        continuations.removeValue(forKey: request)?.resume(throwing: ModelProviderError.connectionFailed)
        callbacks.removeValue(forKey: request)
    }

    func finishAll() {
        let pending = continuations.values
        continuations = [:]
        callbacks = [:]
        for continuation in pending { continuation.resume(throwing: CancellationError()) }
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
        DevelopmentStep(message: DevelopmentMessage(role: "assistant", content: "Unused test development response"))
    }
}
