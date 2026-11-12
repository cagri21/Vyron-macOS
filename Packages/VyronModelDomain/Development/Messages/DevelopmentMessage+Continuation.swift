extension DevelopmentMessage {
    /// A different provider or model starts from the semantic exchange rather than opaque prior state.
    package func discardingContinuation() -> DevelopmentMessage {
        guard continuation != nil else { return self }
        return DevelopmentMessage(removingContinuationFrom: self)
    }

    private init(removingContinuationFrom message: DevelopmentMessage) {
        role = message.role
        content = message.content
        toolCalls = message.toolCalls
        toolName = message.toolName
        toolCallID = message.toolCallID
        continuation = nil
        images = message.images
        imageObservation = message.imageObservation
    }
}
