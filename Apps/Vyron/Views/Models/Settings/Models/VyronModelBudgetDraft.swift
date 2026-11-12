import VyronCore

struct VyronModelBudgetDraft: Equatable {
    var contextTokens: String
    var maxOutputTokens: String

    init(_ settings: ModelSettings) {
        contextTokens = settings.contextTokens.map(String.init) ?? ""
        maxOutputTokens = settings.maxOutputTokens.map(String.init) ?? ""
    }
}
