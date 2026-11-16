import VyronModelDomain

enum VyronHostedCompatibleOutputLimit {
    static func published(for profile: ModelConnectionProfile, model: String) -> Int? {
        if VyronOpenAIConnectionPreset.matches(profile) {
            return VyronOpenAIModelOutputLimit.published(for: model)
        }
        if VyronGeminiConnectionPreset.matches(profile), geminiStandardTextModels.contains(model) {
            return geminiStandardOutputTokens
        }
        if VyronMetaConnectionPreset.matches(profile) {
            return metaTextModels[model]
        }
        return nil
    }

    // Google AI Studio model specifications. Gemini 4 long decode is a separate request mode.
    private static let geminiStandardOutputTokens = 65_536
    private static let geminiStandardTextModels: Set<String> = [
        "gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-2.5-pro",
        "gemini-3-flash-preview", "gemini-3.1-pro-preview", "gemini-3.1-flash-lite",
        "gemini-3.5-flash-lite", "gemini-3.6-flash", "gemini-3.7-flash", "gemini-3.8-flash",
        "gemini-4-hydrogen", "gemini-4-argon", "gemini-4-carbon"
    ]

    // Meta's Chat Completions configuration for Spark and the published Ember specifications.
    private static let metaTextModels = [
        "muse-spark-1.3": 131_072,
        "muse-ember-1.0": 524_288
    ]
}
