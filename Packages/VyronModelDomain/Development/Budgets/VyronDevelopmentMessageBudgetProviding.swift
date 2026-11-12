/// Model-specific message bounds supplied by the selected inference provider.
package protocol VyronDevelopmentMessageBudgetProviding: ModelProvider {
    func developmentMessageBudget(for model: String) -> VyronDevelopmentMessageBudget
}
