package func boundedDevelopmentMessages(
    base: [DevelopmentMessage],
    exchanges: [DevelopmentExchange],
    maximumBytes: Int = VyronDevelopmentMessageBudget.standard.maximumBytes
) throws -> [DevelopmentMessage] {
    try VyronDevelopmentImageContext.validate(base + exchanges.flatMap(\.messages))
    var retained = exchanges
    func size(_ messages: [DevelopmentMessage]) throws -> Int {
        try VyronDevelopmentImageContext.textMessageBytes(messages)
    }
    guard try size(base) <= maximumBytes else { throw DevelopmentAgentError.contextBudget }
    while try size(base + retained.flatMap(\.messages)) > maximumBytes {
        // User steering remains authoritative even when older tool exchanges are dropped.
        guard retained.count > 1,
            let removable = retained.indices.dropLast().first(where: { index in
                !retained[index].messages.contains(where: { $0.role == "user" && $0.imageObservation == nil })
            })
        else { throw DevelopmentAgentError.contextBudget }
        retained.remove(at: removable)
    }
    return base + retained.flatMap(\.messages)
}
