import Foundation
@testable import VyronCore

actor VyronParallelTestProvider: ModelProvider {
    private let reply: @Sendable (VyronParallelTestRequest) async throws -> DevelopmentMessage
    private var requests: [VyronParallelTestRequest] = []

    init(reply: @escaping @Sendable (VyronParallelTestRequest) async throws -> DevelopmentMessage) {
        self.reply = reply
    }

    func recordedRequests() -> [VyronParallelTestRequest] { requests }

    func models() async throws -> [LocalModel] { [LocalModel(name: "fixture-coder", size: 1)] }

    // Existing provider protocol signatures retain their external boundary contract.
    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        throw ModelProviderError.unsupportedTools
    }

    func developmentModel(
        model: String,
        automaticModelSelection: Bool,
        effort: AgentEffort
    ) async throws -> LocalModel {
        LocalModel(name: "fixture-coder", size: 1, capabilities: ["tools"])
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        try await developmentStep(model: model, messages: messages, effort: effort, mode: mode, externalTools: [])
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode,
        externalTools: [DevelopmentExternalTool]
    ) async throws -> DevelopmentStep {
        let request = VyronParallelTestRequest(
            model: model, mode: mode, messages: messages, tools: externalTools.map(\.name)
        )
        requests.append(request)
        let message = try await reply(request)
        return DevelopmentStep(message: message)
    }
}
