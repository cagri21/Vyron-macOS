import Foundation
@testable import VyronCore

actor VyronContinuationEffortTestProvider: ModelProvider {
    private let selectionError: ModelProviderError?
    private var modelRequests: [VyronContinuationModelSelection] = []
    private var stepEfforts: [AgentEffort] = []

    init(selectionError: ModelProviderError? = nil) {
        self.selectionError = selectionError
    }

    func recordedModelRequests() -> [VyronContinuationModelSelection] { modelRequests }
    func recordedStepEfforts() -> [AgentEffort] { stepEfforts }

    func models() async throws -> [LocalModel] {
        [LocalModel(name: "fixture-coder", size: 1, capabilities: ["tools"])]
    }

    // These signatures implement the existing provider boundary without changing its public contract.
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
        modelRequests.append(VyronContinuationModelSelection(
            model: model, automaticModelSelection: automaticModelSelection, effort: effort
        ))
        if let selectionError { throw selectionError }
        return LocalModel(
            name: automaticModelSelection ? "fixture-\(effort.rawValue)" : model,
            size: 1,
            capabilities: ["tools"]
        )
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        stepEfforts.append(effort)
        return DevelopmentStep(message: DevelopmentMessage(role: "assistant", content: "The checkpoint review is complete."))
    }
}
