import Foundation
import VyronCore

actor VyronWorkCompletionTestProvider: ModelProvider {
    static let answer = "Updated the project notes."
    private var step = 0

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
        step += 1
        let message: DevelopmentMessage
        switch step {
        case 1:
            message = DevelopmentMessage(role: "assistant", toolCalls: [
                DevelopmentToolCall(name: "read_file", arguments: ["path": .string("README.md")])
            ])
        case 2:
            message = DevelopmentMessage(role: "assistant", toolCalls: [
                DevelopmentToolCall(name: "edit_file", arguments: [
                    "path": .string("README.md"),
                    "old_text": .string("A local test project."),
                    "new_text": .string("Updated local project notes.")
                ])
            ])
        case 3:
            message = DevelopmentMessage(role: "assistant", toolCalls: [
                DevelopmentToolCall(name: "run_command", arguments: ["command": .string("swift --version")])
            ])
        default:
            message = DevelopmentMessage(role: "assistant", content: Self.answer)
        }
        return DevelopmentStep(message: message)
    }

    // ModelProvider owns this existing tool-catalog boundary signature.
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
