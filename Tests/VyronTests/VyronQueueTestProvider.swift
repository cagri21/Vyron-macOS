import Foundation
@testable import Vyron
@testable import VyronCore

actor VyronQueueTestProvider: ModelProvider {
    private(set) var requests: [[ChatMessage]] = []
    private(set) var cancellations = 0
    private var pending: [Int: VyronQueueTestRequest] = [:]
    private(set) var developmentRequests: [[DevelopmentMessage]] = []
    private(set) var developmentModes: [DevelopmentMode] = []
    private(set) var developmentToolCatalogs: [[DevelopmentExternalTool]] = []
    private(set) var developmentCancellations = 0
    private var pendingDevelopment: [Int: CheckedContinuation<DevelopmentStep, any Error>] = [:]

    func models() async throws -> [LocalModel] { [LocalModel(name: "queue-test", size: 1)] }

    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        if systemPrompt?.contains("Generate suggested follow-up questions") == true {
            return #"{"questions":[]}"#
        }
        let index = requests.count
        requests.append(messages)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[index] = VyronQueueTestRequest(continuation: continuation, onToken: onToken)
                onToken("Partial answer \(index)")
            }
        } onCancel: {
            Task { await self.cancel(index) }
        }
    }

    func complete(_ index: Int, answer: String) {
        guard let request = pending.removeValue(forKey: index) else { return }
        request.onToken(answer)
        request.continuation.resume(returning: answer)
    }

    func fail(_ index: Int) {
        pending.removeValue(forKey: index)?.continuation.resume(throwing: ModelProviderError.connectionFailed)
    }

    private func cancel(_ index: Int) {
        guard let request = pending.removeValue(forKey: index) else { return }
        cancellations += 1
        request.onToken("STALE_CANCELLED_TOKEN")
        request.continuation.resume(throwing: CancellationError())
    }

    func developmentModel(
        model: String,
        automaticModelSelection: Bool,
        effort: AgentEffort
    ) async throws -> LocalModel { LocalModel(name: model, size: 1, capabilities: ["tools"]) }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        let index = developmentRequests.count
        developmentRequests.append(messages)
        developmentModes.append(mode)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingDevelopment[index] = continuation
            }
        } onCancel: {
            Task { await self.cancelDevelopment(index) }
        }
    }

    func completeDevelopment(_ index: Int, message: DevelopmentMessage) {
        pendingDevelopment.removeValue(forKey: index)?.resume(returning: DevelopmentStep(message: message))
    }

    // Match the provider protocol's tool catalog boundary while retaining this fixture's scripted requests.
    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode,
        externalTools: [DevelopmentExternalTool]
    ) async throws -> DevelopmentStep {
        guard externalTools.allSatisfy({
            ($0.name == "parallel_tasks" && $0.isReadOnly) || VyronWebTools.definitions.contains($0)
                || VyronSkillResourceTools.definitions.contains($0)
                || VyronChatHandoffTools.definitions.contains($0)
                || $0 == VyronLinkedChatTools.definition
                || VyronChromeTools.definitions.contains($0)
                || VyronOfficeTools.definitions.contains($0)
                || VyronMacWorkTools.definitions.contains($0)
                || VyronMacWorkScreenshots.definitions.contains($0)
                || VyronDevelopmentFileOperationTools.definitions.contains($0)
        }) else {
            throw ModelProviderError.unsupportedTools
        }
        developmentToolCatalogs.append(externalTools)
        return try await developmentStep(model: model, messages: messages, effort: effort, mode: mode)
    }

    private func cancelDevelopment(_ index: Int) {
        guard let continuation = pendingDevelopment.removeValue(forKey: index) else { return }
        developmentCancellations += 1
        continuation.resume(throwing: CancellationError())
    }
}
