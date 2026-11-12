import VyronCore

actor VyronConversationMoveTestProvider: ModelProvider {
    let destinationPath: String
    private(set) var receivedDestinationContext = false

    init(destinationPath: String) {
        self.destinationPath = destinationPath
    }

    func models() async throws -> [LocalModel] { [] }

    func chat(
        model: String, messages: [ChatMessage], systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        #"{"questions":[]}"#
    }

    func developmentModel(
        model: String, automaticModelSelection: Bool, effort: AgentEffort
    ) async throws -> LocalModel {
        LocalModel(name: model, size: 1, capabilities: ["tools"])
    }

    func developmentStep(
        model: String, messages: [DevelopmentMessage], effort: AgentEffort, mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        if messages.contains(where: { $0.role == "tool" && $0.toolName == "open_project_folder" }) {
            return DevelopmentStep(message: DevelopmentMessage(role: "assistant", content: "Folder request resolved."))
        }
        receivedDestinationContext = messages.contains { $0.content.contains(destinationPath) }
        return DevelopmentStep(message: DevelopmentMessage(role: "assistant", toolCalls: [
            DevelopmentToolCall(name: "open_project_folder", arguments: ["path": .string(destinationPath)])
        ]))
    }

    // Keep the existing provider tool-catalog boundary for interactive Work.
    func developmentStep(
        model: String, messages: [DevelopmentMessage], effort: AgentEffort,
        mode: DevelopmentMode, externalTools: [DevelopmentExternalTool]
    ) async throws -> DevelopmentStep {
        try await developmentStep(model: model, messages: messages, effort: effort, mode: mode)
    }
}
