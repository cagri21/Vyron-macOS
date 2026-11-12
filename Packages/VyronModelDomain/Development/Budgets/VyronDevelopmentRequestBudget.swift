import Foundation

/// Bounds the final provider representation without splitting a tool exchange or dropping user guidance.
package enum VyronDevelopmentRequestBudget {
    package static let requestOverheadTokens = 2_048

    package static func messages(
        _ messages: [DevelopmentMessage],
        budget: VyronDevelopmentContextBudget,
        measureToolBytes: () throws -> Int,
        encodedMessageBytes: ([DevelopmentMessage]) throws -> Int = { try JSONEncoder().encode($0).count }
    ) throws -> [DevelopmentMessage] {
        try VyronDevelopmentImageContext.validate(messages)
        let toolBytes = try budget.encodedToolBytes ?? measureToolBytes()
        let contextBytes = budget.contextTokens - toolBytes - requestOverheadTokens - budget.outputTokens
        guard contextBytes > 0 else { throw DevelopmentAgentError.contextBudget }
        return try boundedMessages(
            messages,
            maximumMessageBytes: budget.maximumMessageBytes,
            maximumContextBytes: contextBytes,
            encodedMessageBytes: encodedMessageBytes
        )
    }

    package static func byteBoundedMessages(
        _ messages: [DevelopmentMessage],
        maximumMessageBytes: Int,
        encodedMessageBytes: ([DevelopmentMessage]) throws -> Int = { try JSONEncoder().encode($0).count }
    ) throws -> [DevelopmentMessage] {
        try VyronDevelopmentImageContext.validate(messages)
        return try boundedMessages(
            messages,
            maximumMessageBytes: maximumMessageBytes,
            maximumContextBytes: nil,
            encodedMessageBytes: encodedMessageBytes
        )
    }

    private static func boundedMessages(
        _ messages: [DevelopmentMessage],
        maximumMessageBytes: Int,
        maximumContextBytes: Int?,
        encodedMessageBytes: ([DevelopmentMessage]) throws -> Int
    ) throws -> [DevelopmentMessage] {
        var retained = exchanges(in: messages)
        while true {
            let candidate = retained.flatMap(\.messages)
            let rawBytes = try VyronDevelopmentImageContext.textMessageBytes(candidate)
            let wireBytes = try encodedMessageBytes(VyronDevelopmentImageContext.messagesWithoutImages(candidate))
            let imageTokens =
                VyronDevelopmentImageContext.imageCount(in: candidate)
                * VyronImageAttachment.estimatedContextTokens
            let fitsContext = maximumContextBytes.map { wireBytes + imageTokens <= $0 } ?? true
            if rawBytes <= maximumMessageBytes, wireBytes <= maximumMessageBytes, fitsContext {
                return candidate
            }
            let latestAssistant = retained.lastIndex { $0.messages.first?.role == "assistant" }
            let latestCapture = retained.lastIndex { isCaptureExchange($0) }
            guard
                let removable = retained.indices.first(where: { index in
                    (index != latestAssistant && retained[index].messages.first?.role == "assistant")
                        || (index != latestCapture && isCaptureExchange(retained[index]))
                })
            else { throw DevelopmentAgentError.contextBudget }
            retained.remove(at: removable)
        }
    }

    private static func isCaptureExchange(_ exchange: DevelopmentExchange) -> Bool {
        !exchange.messages.isEmpty
            && exchange.messages.allSatisfy {
                $0.role == "user" && $0.imageObservation != nil && $0.toolCalls == nil
                    && $0.toolName == nil && $0.toolCallID == nil
            }
    }

    package static func compactingCompletedExchanges(in messages: [DevelopmentMessage]) -> [DevelopmentMessage] {
        exchanges(in: messages).flatMap { exchange in
            guard let assistant = exchange.messages.first, assistant.role == "assistant",
                let calls = assistant.toolCalls, !calls.isEmpty,
                exchange.messages.count == calls.count + 1
            else { return exchange.messages }
            var pending = calls
            for result in exchange.messages.dropFirst() {
                guard result.role == "tool",
                    let index = pending.firstIndex(where: { call in
                        if let resultID = result.toolCallID, let callID = call.id { return resultID == callID }
                        return result.toolName == call.function.name
                    })
                else { return exchange.messages }
                pending.remove(at: index)
            }
            return VyronDevelopmentExchangeCompactor.compact(exchange).messages
        }
    }

    private static func exchanges(in messages: [DevelopmentMessage]) -> [DevelopmentExchange] {
        var exchanges: [DevelopmentExchange] = []
        for message in messages {
            if message.role == "tool", let last = exchanges.last, last.messages.first?.role == "assistant" {
                exchanges[exchanges.count - 1] = DevelopmentExchange(messages: last.messages + [message])
            } else {
                exchanges.append(DevelopmentExchange(messages: [message]))
            }
        }
        return exchanges
    }
}
