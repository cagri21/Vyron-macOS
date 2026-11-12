package struct DevelopmentExchange: Sendable {
    package let messages: [DevelopmentMessage]

    package init(messages: [DevelopmentMessage]) {
        self.messages = messages
    }
}
