import Foundation
import VyronCore

actor VyronTerminalTestProvider: ModelProvider {
    private(set) var requests: [[DevelopmentMessage]] = []

    func models() async throws -> [LocalModel] { [] }

    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        #"{"questions":[]}"#
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
        requests.append(messages)
        let message: DevelopmentMessage
        switch requests.count {
        case 1, 3:
            message = DevelopmentMessage(role: "assistant", toolCalls: [
                DevelopmentToolCall(name: "run_command", arguments: ["command": .string("swift --version")])
            ])
        case 2:
            message = DevelopmentMessage(role: "assistant", toolCalls: [
                DevelopmentToolCall(name: "request_user_input", arguments: [
                    "questions": .array([.object([
                        "id": .string("scope"),
                        "question": .string("Which scope should I continue with?")
                    ])])
                ])
            ])
        default:
            message = DevelopmentMessage(role: "assistant", content: "Finished the requested inspection.")
        }
        return DevelopmentStep(message: message)
    }

    // The provider protocol owns this existing five-argument tool-catalog boundary.
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
