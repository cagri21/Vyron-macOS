import Foundation
@testable import VyronCore

actor VyronFileOperationTestProvider: ModelProvider {
    private let provider: VyronSteeringTestProvider
    private var tools: [[String]] = []

    init(calls: [DevelopmentToolCall]) {
        provider = VyronSteeringTestProvider { round, _ in
            round <= calls.count
                ? DevelopmentMessage(role: "assistant", toolCalls: [calls[round - 1]])
                : DevelopmentMessage(role: "assistant", content: "The requested actions are finished.")
        }
    }

    func recordedTools() -> [[String]] { tools }

    func models() async throws -> [LocalModel] { try await provider.models() }

    // These required signatures implement the existing provider boundary without changing its contract.
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
        try await provider.developmentModel(
            model: model, automaticModelSelection: automaticModelSelection, effort: effort
        )
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        try await provider.developmentStep(model: model, messages: messages, effort: effort, mode: mode)
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode,
        externalTools: [DevelopmentExternalTool]
    ) async throws -> DevelopmentStep {
        tools.append(externalTools.map(\.name))
        return try await provider.developmentStep(model: model, messages: messages, effort: effort, mode: mode)
    }
}
