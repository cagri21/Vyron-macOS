import Foundation
@testable import VyronCore

/// Keeps inference entirely in memory so navigation can be exercised during an active request.
actor VyronPluginsTestProvider: ModelProvider {
    private(set) var answerRequests = 0
    private(set) var answerCancellations = 0
    private var answerContinuation: CheckedContinuation<String, any Error>?
    private var onToken: (@Sendable (String) -> Void)?

    func models() async throws -> [LocalModel] {
        [LocalModel(name: "plugins-navigation-test", size: 1)]
    }

    // The parameter shape is required by the existing ModelProvider boundary.
    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        if systemPrompt?.contains("Generate suggested follow-up questions") == true {
            return #"{"questions":[]}"#
        }
        answerRequests += 1
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.onToken = onToken
                answerContinuation = continuation
            }
        } onCancel: {
            Task { await self.cancelOutstandingAnswer() }
        }
    }

    func completeAnswer() {
        let continuation = answerContinuation
        answerContinuation = nil
        let token = onToken
        onToken = nil
        let answer = "The existing request completed after opening Plugins."
        token?(answer)
        continuation?.resume(returning: answer)
    }

    func cancelOutstandingAnswer() {
        guard let continuation = answerContinuation else { return }
        answerContinuation = nil
        onToken = nil
        answerCancellations += 1
        continuation.resume(throwing: CancellationError())
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
