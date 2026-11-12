extension DevelopmentAgent {
    static func steeringExchange(_ updates: [VyronSteeringMessage]) -> DevelopmentExchange {
        DevelopmentExchange(messages: updates.map { update in
            DevelopmentMessage(role: "user", content: update.content)
        })
    }

    static func skippedToolMessage(_ call: DevelopmentToolCall, maximumBytes: Int) -> DevelopmentMessage {
        DevelopmentMessage(
            role: "tool",
            content: toolResponse(
                ok: false,
                output: "Not executed: the user supplied new guidance. Reconsider this action using the latest update.",
                maximumBytes: maximumBytes
            ),
            toolName: call.function.name,
            toolCallID: call.id
        )
    }
}
