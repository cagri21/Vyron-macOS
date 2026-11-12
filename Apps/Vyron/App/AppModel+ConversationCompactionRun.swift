import VyronCore

extension AppModel {
    func runCompaction(
        _ compaction: VyronConversationCompactionSubmission,
        response: VyronResponseIdentity,
        inference: VyronConversationInferenceSelection
    ) async throws {
        let summary = try await VyronChatInference.response(
            using: inference.provider,
            request: VyronChatInferenceRequest(
                model: inference.model,
                messages: Self.compactionRequestMessages(compaction.request, command: compaction.command),
                configuration: VyronChatInferenceConfiguration(
                    systemPrompt: VyronConversationCompactionContext.summarySystemPrompt,
                    effort: inference.effort
                )
            ),
            onToken: { _ in }
        )
        guard foregroundRun.owns(response), !Task.isCancelled, !isShuttingDown else { return }
        try saveCompaction(summary, response: response, limited: compaction.request.wasTruncated)
        if foregroundRun.activeGeneration == response.generationID { statusMessage = VyronCompactionText.completed }
        finishConversationResponse(response)
    }
}
