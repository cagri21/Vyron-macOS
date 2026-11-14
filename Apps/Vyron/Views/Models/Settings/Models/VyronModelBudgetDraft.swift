import VyronCore

struct VyronModelBudgetDraft: Equatable {
    var contextTokens: String
    var maxOutputTokens: String
    var ollamaDevelopmentTimeoutSeconds: String

    init(_ settings: ModelSettings) {
        contextTokens = settings.contextTokens.map(String.init) ?? ""
        maxOutputTokens = settings.maxOutputTokens.map(String.init) ?? ""
        ollamaDevelopmentTimeoutSeconds = settings.ollamaDevelopmentTimeoutSeconds.map(String.init) ?? ""
    }
}
