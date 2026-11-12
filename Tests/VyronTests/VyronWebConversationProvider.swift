import Foundation
import VyronCore

actor VyronWebConversationProvider: ModelProvider {
    private(set) var receivedMessages: [[ChatMessage]] = []
    private(set) var systemPrompts: [String?] = []
    private(set) var developmentRequests = 0

    func models() async throws -> [LocalModel] { [] }

    // The existing inference protocol owns this boundary's four-argument signature.
    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        if systemPrompt?.contains("Generate suggested follow-up questions") == true {
            return #"{"questions":[]}"#
        }
        receivedMessages.append(messages)
        systemPrompts.append(systemPrompt)
        let answer = "Web answer \(receivedMessages.count) grounded in supplied evidence."
        onToken(answer)
        return answer
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
        developmentRequests += 1
        return DevelopmentStep(message: DevelopmentMessage(role: "assistant", content: "Unexpected project path"))
    }
}
