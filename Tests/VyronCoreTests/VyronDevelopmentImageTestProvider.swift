import Foundation
@testable import VyronCore

actor VyronDevelopmentImageTestProvider: ModelProvider {
    private(set) var automaticSelection: Bool?
    private(set) var receivedMessages: [DevelopmentMessage] = []

    func models() async throws -> [LocalModel] {
        [LocalModel(name: "vision-model", size: 0, capabilities: ["tools", "vision"])]
    }

    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        throw ModelProviderError.invalidResponse("The test expects the development path.")
    }

    func developmentModel(
        model: String,
        automaticModelSelection: Bool,
        effort: AgentEffort
    ) async throws -> LocalModel {
        automaticSelection = automaticModelSelection
        return LocalModel(name: model, size: 0, capabilities: ["tools", "vision"])
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        receivedMessages = messages
        return DevelopmentStep(message: DevelopmentMessage(
            role: "assistant", content: "The attached interface has a sidebar and a conversation composer."
        ))
    }
}
