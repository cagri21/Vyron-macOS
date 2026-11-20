import VyronModelDomain

struct VyronOllamaDevelopmentAllocation: Sendable {
    let contextTokens: Int
    let outputTokens: Int
    let messageBudget: VyronDevelopmentMessageBudget
}
