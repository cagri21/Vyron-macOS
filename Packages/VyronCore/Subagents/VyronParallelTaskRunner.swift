import Foundation
import VyronDevelopment

struct VyronParallelTaskRunner: Sendable {
    let client: any ModelProvider
    let projectURL: URL
    let onEvent: @Sendable (VyronSubagentEvent) -> Void

    func run(
        _ tasks: [VyronParallelTask],
        context: VyronParallelTaskContext,
        maximumResponseBytes: Int
    ) async throws -> String {
        let identities = tasks.map {
            VyronSubagentIdentity(name: $0.name, prompt: $0.prompt, model: context.model)
        }
        let results = try await withThrowingTaskGroup(of: VyronParallelTaskResult.self) { group in
            for identity in identities {
                group.addTask { await run(identity, context: context) }
            }
            var results: [VyronParallelTaskResult] = []
            for try await result in group { results.append(result) }
            try Task.checkCancellation()
            return results.sorted { left, right in
                let leftIndex = identities.firstIndex { $0.id == left.identity.id } ?? 0
                let rightIndex = identities.firstIndex { $0.id == right.identity.id } ?? 0
                return leftIndex < rightIndex
            }
        }
        return try Self.response(results, maximumBytes: maximumResponseBytes)
    }

    static func response(_ results: [VyronParallelTaskResult], maximumBytes: Int) throws -> String {
        var summaryBytes = VyronParallelTaskLimits.maximumSummaryBytes
        while true {
            // Stable one-based task indices retain every outcome even when the tool budget is tight.
            let replies = results.enumerated().map { index, result in
                VyronParallelTaskReply(
                    task: index + 1,
                    state: result.completion.state,
                    summary: boundedAgentPrefix(result.completion.summary, bytes: summaryBytes),
                    truncated: result.completion.summary.utf8.count > summaryBytes
                )
            }
            let output = String(decoding: try JSONEncoder().encode(replies), as: UTF8.self)
            let response = DevelopmentAgent.toolResponse(ok: true, output: output, maximumBytes: maximumBytes)
            let envelope = try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: Data(response.utf8))
            if envelope["truncated"] == .bool(false) { return response }
            guard summaryBytes > 0 else { throw DevelopmentAgentError.contextBudget }
            summaryBytes = summaryBytes > 4 ? summaryBytes * 3 / 4 : 0
        }
    }

    private func run(
        _ identity: VyronSubagentIdentity,
        context: VyronParallelTaskContext
    ) async -> VyronParallelTaskResult {
        onEvent(VyronSubagentEvent(identity: identity, update: .started))
        let completion: VyronSubagentCompletion
        do {
            try Task.checkCancellation()
            // Separate observation ownership prevents a child from resetting the parent's read/edit scope.
            let workspace = try DevelopmentWorkspace(rootURL: projectURL)
            let child = DevelopmentAgent(client: client, workspace: workspace)
            let result = try await child.run(
                goal: identity.prompt,
                model: context.model,
                automaticModelSelection: false,
                effort: context.effort,
                mode: .plan,
                conversationContext: context.conversation,
                onEvent: { event in
                    onEvent(VyronSubagentEvent(identity: identity, update: .activity(event)))
                },
                approveCommand: { _ in false }
            )
            try Task.checkCancellation()
            completion = VyronSubagentCompletion(
                state: .completed,
                summary: boundedAgentPrefix(result.finalMessage, bytes: VyronParallelTaskLimits.maximumSummaryBytes)
            )
        } catch {
            let cancelled = error is CancellationError || Task.isCancelled || (error as? URLError)?.code == .cancelled
            completion = VyronSubagentCompletion(
                state: cancelled ? .stopped : .failed,
                summary: cancelled ? "Stopped with the parent task." : String(error.localizedDescription.prefix(1_000))
            )
        }
        onEvent(VyronSubagentEvent(identity: identity, update: .finished(completion)))
        return VyronParallelTaskResult(identity: identity, completion: completion)
    }
}
