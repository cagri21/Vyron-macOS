import Foundation
@testable import VyronCore

actor VyronWorkBudgetTestProvider: ModelProvider {
    private(set) var messages: [DevelopmentMessage] = []

    func models() async throws -> [LocalModel] { [selected] }

    private var selected: LocalModel {
        LocalModel(name: "gpt-6.1-sol", size: 0, capabilities: ["tools"])
    }

    func developmentModel(
        model: String,
        automaticModelSelection: Bool,
        effort: AgentEffort
    ) async throws -> LocalModel {
        selected
    }

    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        throw ModelProviderError.unsupportedTools
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        self.messages = messages
        return DevelopmentStep(message: DevelopmentMessage(role: "assistant", content: "Inspection complete."))
    }

    // Stable ModelProvider interoperability requires this signature.
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
