import Foundation
import VyronCore

actor VyronMacWorkIntegrationProvider: ModelProvider {
    nonisolated static let applicationID = "com.example.PreviewApp"
    nonisolated static let sourceID = "window-work-integration"
    nonisolated static let windowsCallID = "work-window-list"
    nonisolated static let screenshotCallID = "work-window-capture"

    private(set) var requests: [[DevelopmentMessage]] = []
    private(set) var toolCatalogs: [[DevelopmentExternalTool]] = []
    private(set) var requestedModels: [String] = []
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
        return "Unexpected Chat inference."
    }

    func developmentModel(
        model: String, automaticModelSelection: Bool, effort: AgentEffort
    ) async throws -> LocalModel {
        automaticSelections.append(automaticModelSelection)
        return LocalModel(name: model, size: 1, capabilities: ["vision", "tools"])
    }

    func developmentStep(
        model: String, messages: [DevelopmentMessage], effort: AgentEffort, mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        try await developmentStep(model: model, messages: messages, effort: effort, mode: mode, externalTools: [])
    }

    // The existing provider protocol defines this five-argument transport boundary.
    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode,
        externalTools: [DevelopmentExternalTool]
    ) async throws -> DevelopmentStep {
        requests.append(messages)
        toolCatalogs.append(externalTools)
        requestedModels.append(model)
        let call: DevelopmentToolCall
        switch requests.count {
        case 1:
            call = DevelopmentToolCall(
                name: "vyron_mac_windows", arguments: ["application_id": .string(Self.applicationID)],
                id: Self.windowsCallID
            )
        case 2:
            call = DevelopmentToolCall(
                name: "vyron_mac_screenshot", arguments: ["source_id": .string(Self.sourceID)],
                id: Self.screenshotCallID
            )
        default:
            return DevelopmentStep(message: DevelopmentMessage(
                role: "assistant", content: "Captured and checked the requested application window."
            ))
        }
        return DevelopmentStep(message: DevelopmentMessage(role: "assistant", toolCalls: [call]))
    }
}
