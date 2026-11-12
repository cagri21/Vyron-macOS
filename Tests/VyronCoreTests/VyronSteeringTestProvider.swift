import Foundation
@testable import VyronCore

/// A deterministic provider that can deliver user guidance while inference is suspended.
actor VyronSteeringTestProvider: VyronDevelopmentMessageBudgetProviding {
    private static let modelName = "fixture-coder"
    private nonisolated let messageBudget: VyronDevelopmentMessageBudget
    private let reply: @Sendable (Int, [DevelopmentMessage]) async throws -> DevelopmentMessage
    private var requests: [[DevelopmentMessage]] = []

    init(
        messageBudget: VyronDevelopmentMessageBudget = .standard,
        reply: @escaping @Sendable (Int, [DevelopmentMessage]) async throws -> DevelopmentMessage
    ) {
        self.messageBudget = messageBudget
        self.reply = reply
    }

    nonisolated func developmentMessageBudget(for model: String) -> VyronDevelopmentMessageBudget {
        model == Self.modelName ? messageBudget : .standard
    }

    func recordedRequests() -> [[DevelopmentMessage]] { requests }

    func models() async throws -> [LocalModel] {
        [LocalModel(name: Self.modelName, size: 1)]
    }

    // These signatures implement the existing provider boundary without changing its contract.
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
        LocalModel(name: Self.modelName, size: 1, capabilities: ["tools"])
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        requests.append(messages)
        let message = try await reply(requests.count, messages)
        return DevelopmentStep(message: message)
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
