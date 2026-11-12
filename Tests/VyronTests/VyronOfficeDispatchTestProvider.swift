import Foundation
import VyronCore

actor VyronOfficeDispatchTestProvider: ModelProvider {
    static let answer = "Rendered the requested PDF page locally. The source document was preserved."
    private(set) var catalogs: [[DevelopmentExternalTool]] = []
    private(set) var modes: [DevelopmentMode] = []
    private(set) var officeResults: [String] = []

    func models() async throws -> [LocalModel] { [] }

    // The established provider protocol owns this inference boundary.
    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        if systemPrompt?.contains("Generate suggested follow-up questions") == true {
            return #"{"questions":[]}"#
        }
        throw ModelProviderError.invalidResponse("The Office dispatch fixture must use project Work or Plan.")
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
        try await developmentStep(model: model, messages: messages, effort: effort, mode: mode, externalTools: [])
    }

    // The existing protocol supplies the project tool catalog as a fifth boundary argument.
    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode,
        externalTools: [DevelopmentExternalTool]
    ) async throws -> DevelopmentStep {
        catalogs.append(externalTools)
        modes.append(mode)
        if mode == .plan {
            return DevelopmentStep(message: DevelopmentMessage(
                role: "assistant", content: "Office page rendering would require Work and native review."
            ))
        }
        guard externalTools.contains(where: { $0.name == "office_render" && !$0.isReadOnly }) else {
            throw ModelProviderError.unsupportedTools
        }
        if let result = messages.last(where: { $0.role == "tool" && $0.toolName == "office_render" }) {
            let envelope = try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: Data(result.content.utf8))
            guard envelope["ok"] == .bool(true) else {
                throw ModelProviderError.invalidResponse("The requested local Office operation did not succeed.")
            }
            officeResults.append(result.content)
            return DevelopmentStep(message: DevelopmentMessage(role: "assistant", content: Self.answer))
        }
        return DevelopmentStep(message: DevelopmentMessage(role: "assistant", toolCalls: [
            DevelopmentToolCall(name: "office_render", arguments: [
                "input_path": .string("report.pdf"),
                "output_path": .string("previews"),
                "pages": .array([.number(1)])
            ], id: "office-preview-1")
        ]))
    }
}
