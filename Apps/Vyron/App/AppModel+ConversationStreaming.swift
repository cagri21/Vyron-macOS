import VyronCore

extension AppModel {
    func streamConversationReply(
        using provider: any ModelProvider,
        request: VyronChatInferenceRequest,
        response: VyronResponseIdentity
    ) async throws -> String {
        try await foregroundRun.streamResponse(response, receive: { [weak self] token in
            self?.appendToken(token, conversationID: response.conversationID, messageID: response.messageID)
        }, perform: { continuation in
            try await VyronChatInference.response(using: provider, request: request) { token in
                continuation.yield(token)
            }
        })
    }

    func runWithDevelopmentEvents(
        _ events: AsyncStream<VyronTrackedRunEvent>,
        continuation: AsyncStream<VyronTrackedRunEvent>.Continuation,
        tracking: VyronDevelopmentResponseTracking,
        operation: () async throws -> DevelopmentResult
    ) async throws -> DevelopmentResult {
        async let drain: Void = recordDevelopmentEvents(events, response: tracking.response)
        do {
            let result = try await operation()
            continuation.finish()
            await drain
            recordResponseChanges(await tracking.agent.responseChanges(), response: tracking.response)
            return result
        } catch {
            continuation.finish()
            await drain
            recordResponseChanges(await tracking.agent.responseChanges(), response: tracking.response)
            throw error
        }
    }

    private func recordDevelopmentEvents(
        _ events: AsyncStream<VyronTrackedRunEvent>,
        response: VyronResponseIdentity
    ) async {
        for await event in events {
            guard foregroundRun.owns(response), !Task.isCancelled else { return }
            switch event {
            case .development(let update):
                handleDevelopmentEvent(update, conversationID: response.conversationID, messageID: response.messageID)
            case .subagent(let update):
                recordSubagentEvent(update, conversationID: response.conversationID, messageID: response.messageID)
            }
        }
    }
}
