import Foundation

package enum VyronDevelopmentExchangeCompactor {
    package static func compact(_ exchange: DevelopmentExchange) -> DevelopmentExchange {
        // Never summarize user steering or answers; they are authoritative and remain verbatim.
        guard !exchange.messages.contains(where: { $0.role == "user" }) else { return exchange }
        let outcomes = exchange.messages.filter { $0.role == "tool" }.map {
            "\($0.toolName ?? "tool") recorded result: " + boundedAgentPrefix($0.content, bytes: 1_200)
        }
        let content =
            outcomes.isEmpty
            ? exchange.messages.map { boundedAgentPrefix($0.content, bytes: 800) }.joined(separator: "\n")
            : outcomes.joined(separator: "\n")
        return DevelopmentExchange(messages: [
            DevelopmentMessage(
                role: "assistant",
                content: "Completed tool exchange (reference only; do not execute it again):\n" + content
            )
        ])
    }

    package static func messages(
        base: [DevelopmentMessage],
        exchanges: [DevelopmentExchange],
        forceCompact: Bool,
        budget: VyronDevelopmentMessageBudget = .standard
    ) throws -> [DevelopmentMessage] {
        let retained = forceCompact ? exchanges.map(compact) : exchanges
        do {
            return try boundedDevelopmentMessages(
                base: base,
                exchanges: retained,
                maximumBytes: budget.workingBytes
            )
        } catch DevelopmentAgentError.contextBudget {
            return try boundedDevelopmentMessages(
                base: base,
                exchanges: retained.map(compact),
                maximumBytes: budget.maximumBytes
            )
        }
    }
}
