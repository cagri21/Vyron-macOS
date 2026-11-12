public enum VyronChatInference {
    public static func response(
        using provider: any ModelProvider,
        request: VyronChatInferenceRequest,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try Task.checkCancellation()
        if let capable = provider as? any VyronEffortChatProviding {
            return try await capable.chat(request, onToken: onToken)
        }
        return try await provider.chat(
            model: request.model,
            messages: request.messages,
            systemPrompt: request.configuration.systemPrompt,
            onToken: onToken
        )
    }
}
