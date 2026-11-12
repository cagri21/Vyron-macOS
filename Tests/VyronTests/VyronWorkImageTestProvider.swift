import Foundation
import VyronCore

actor VyronWorkImageTestProvider: ModelProvider {
    private(set) var requests: [[DevelopmentMessage]] = []
    private(set) var requestedModels: [String] = []
    private(set) var requestedModes: [DevelopmentMode] = []
    private(set) var automaticSelections: [Bool] = []
    private(set) var chatRequests = 0

    func models() async throws -> [LocalModel] { [] }

    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        if systemPrompt?.contains("Generate suggested follow-up questions") == true {
            return #"{"questions":[]}"#
        }
        chatRequests += 1
        return "Unexpected Chat request."
    }

    func developmentModel(
        model: String,
        automaticModelSelection: Bool,
        effort: AgentEffort
    ) async throws -> LocalModel {
        automaticSelections.append(automaticModelSelection)
        return LocalModel(
            name: automaticModelSelection ? "text-only-fallback" : model,
            size: 1,
            capabilities: ["vision", "tools"]
        )
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        requests.append(messages)
        requestedModels.append(model)
        requestedModes.append(mode)
        return DevelopmentStep(message: DevelopmentMessage(
            role: "assistant",
            content: "The screenshot is available for this read-only explanation. No project changes were requested."
        ))
    }

    // The provider protocol defines this existing five-argument tool-catalog boundary.
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
