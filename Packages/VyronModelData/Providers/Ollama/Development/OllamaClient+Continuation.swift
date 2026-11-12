import VyronModelDomain

extension OllamaClient {
    /// Hosted-provider state is not part of Ollama's message schema or its context budget.
    nonisolated static func messagesWithoutContinuation(_ messages: [DevelopmentMessage]) -> [DevelopmentMessage] {
        messages.map { $0.discardingContinuation() }
    }
}
