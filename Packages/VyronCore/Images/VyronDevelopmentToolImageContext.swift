/// Delivers bounded native capture evidence after a complete tool exchange, preserving real user references.
enum VyronDevelopmentToolImageContext {
    static func observation(tool: String, images: [VyronImageAttachment]) throws -> DevelopmentMessage? {
        guard !images.isEmpty else { return nil }
        let message = DevelopmentMessage(observation: VyronDevelopmentImageObservation(tool: tool), images: images)
        try VyronDevelopmentImageContext.validate([message])
        return message
    }

    static func appending(
        _ observations: [DevelopmentMessage],
        to exchanges: [DevelopmentExchange],
        base: [DevelopmentMessage]
    ) throws -> [DevelopmentExchange] {
        guard !observations.isEmpty else { return exchanges }
        let priorObservations = exchanges.flatMap(\.messages).filter(isObservation).map { message in
            DevelopmentMessage(
                observation: VyronDevelopmentImageObservation(
                    tool: message.imageObservation?.tool ?? "capture",
                    omittedImageNames: message.imageObservation?.omittedImageNames ?? [],
                    textEvidence: message.imageObservation?.textEvidence,
                    isHistorical: true
                ),
                images: message.images ?? []
            )
        }
        let candidates = priorObservations + observations
        let retainedObservations = Array(candidates.suffix(VyronImageAttachment.maximumCount))
        let evictedImageNames = candidates.dropLast(retainedObservations.count).flatMap { message in
            (message.images ?? []).map(\.name)
        }
        let retained = exchanges.compactMap { exchange -> DevelopmentExchange? in
            let messages = exchange.messages.filter { !isObservation($0) }
            return messages.isEmpty ? nil : DevelopmentExchange(messages: messages)
        }
        let originalMessages = base + retained.flatMap(\.messages)
        try VyronDevelopmentImageContext.validate(originalMessages)
        let originalImages = originalMessages.flatMap { $0.images ?? [] }
        var remainingCount = VyronImageAttachment.maximumCount - originalImages.count
        var remainingBytes = VyronImageAttachment.maximumRequestDataBytes
            - originalImages.reduce(0) { $0 + $1.data.count }
        var bounded: [DevelopmentMessage] = []
        for (offset, message) in retainedObservations.reversed().enumerated() {
            guard let marker = message.imageObservation, isObservation(message) else {
                throw DevelopmentAgentError.invalidTool("Screenshot evidence must be a native user-role observation.")
            }
            try VyronDevelopmentImageContext.validate([message])
            var selected: [VyronImageAttachment] = []
            var omitted = marker.omittedImageNames
            if offset == 0 { omitted += evictedImageNames }
            for image in (message.images ?? []).reversed() {
                guard remainingCount > 0, image.data.count <= remainingBytes else {
                    omitted.insert(image.name, at: 0)
                    continue
                }
                selected.append(image)
                remainingCount -= 1
                remainingBytes -= image.data.count
            }
            bounded.append(DevelopmentMessage(
                observation: VyronDevelopmentImageObservation(
                    tool: marker.tool,
                    omittedImageNames: omitted,
                    textEvidence: marker.textEvidence,
                    isHistorical: marker.isHistorical == true
                ),
                images: Array(selected.reversed())
            ))
        }
        let result = retained + bounded.reversed().map { DevelopmentExchange(messages: [$0]) }
        try VyronDevelopmentImageContext.validate(base + result.flatMap(\.messages))
        return result
    }

    private static func isObservation(_ message: DevelopmentMessage) -> Bool {
        message.imageObservation != nil && message.role == "user" && message.toolCalls == nil
            && message.toolName == nil && message.toolCallID == nil
    }
}
