import Foundation
import VyronCore

actor VyronScreenshotTestProvider: ModelProvider {
    private(set) var receivedMessages: [[ChatMessage]] = []
    private(set) var receivedModels: [String] = []
    private(set) var receivedSystemPrompts: [String?] = []
    private(set) var developmentRequests = 0

    func models() async throws -> [LocalModel] { [] }

    // Inference protocol signatures are an existing provider boundary.
    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        if systemPrompt?.contains("Generate suggested follow-up questions") == true {
            return #"{"questions":[]}"#
        }
        receivedModels.append(model)
        receivedMessages.append(messages)
        receivedSystemPrompts.append(systemPrompt)
        let answer = "Screenshot analysis \(receivedMessages.count)."
        onToken(answer)
        return answer
    }

    func developmentModel(
        model: String,
        automaticModelSelection: Bool,
        effort: AgentEffort
    ) async throws -> LocalModel {
        LocalModel(name: model, size: 1, capabilities: ["vision", "tools"])
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        developmentRequests += 1
        return DevelopmentStep(message: DevelopmentMessage(role: "assistant", content: "Unexpected agent path"))
    }
}
