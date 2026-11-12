import Foundation
@testable import VyronCore

actor VyronAutomaticCycleTestProvider: ModelProvider {
    private let reply: @Sendable (Int, [DevelopmentMessage]) async throws -> DevelopmentMessage
    private var requests: [VyronAutomaticCycleTestRequest] = []
    private var selections: [VyronContinuationModelSelection] = []

    init(reply: @escaping @Sendable (Int, [DevelopmentMessage]) async throws -> DevelopmentMessage) {
        self.reply = reply
    }

    func recordedRequests() -> [VyronAutomaticCycleTestRequest] { requests }
    func recordedSelections() -> [VyronContinuationModelSelection] { selections }

    func models() async throws -> [LocalModel] {
        [LocalModel(name: "fixture-coder", size: 1, capabilities: ["tools"])]
    }

    // Retain the existing provider protocol's framework boundary signatures.
    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        throw ModelProviderError.unsupportedTools
    }

    func developmentModel(
        model: String,
        automaticModelSelection: Bool,
        effort: AgentEffort
    ) async throws -> LocalModel {
        selections.append(VyronContinuationModelSelection(
            model: model, automaticModelSelection: automaticModelSelection, effort: effort
        ))
        return LocalModel(name: model, size: 1, capabilities: ["tools"])
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        requests.append(VyronAutomaticCycleTestRequest(
            model: model, messages: messages, effort: effort, mode: mode
        ))
        let message = try await reply(requests.count, messages)
        return DevelopmentStep(message: message)
    }
}
