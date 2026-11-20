/// Providers with verified runtime context limits can reserve tools and output before agent compaction.
package protocol VyronDevelopmentAdaptiveBudgetProviding: ModelProvider {
    func developmentBudget(for request: VyronDevelopmentBudgetRequest) async throws -> VyronDevelopmentMessageBudget
}
