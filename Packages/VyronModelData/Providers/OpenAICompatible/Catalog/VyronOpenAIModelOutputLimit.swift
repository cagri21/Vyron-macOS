enum VyronOpenAIModelOutputLimit {
    static func published(for model: String) -> Int? {
        if VyronOpenAIResponsesRoute.modelFamily(for: model) != nil || expandedTextModels.contains(model) {
            return 128_000
        }
        if gpt41Models.contains(model) { return 32_768 }
        if gpt4oModels.contains(model) { return 16_384 }
        return nil
    }

    // OpenAI's model catalog and its documented model IDs or dated snapshots.
    private static let expandedTextModels: Set<String> = [
        "gpt-5", "gpt-5-2025-08-07", "gpt-5-mini", "gpt-5-mini-2025-08-07",
        "gpt-5-nano", "gpt-5-nano-2025-08-07", "gpt-5.1", "gpt-5.1-2025-11-13",
        "gpt-5.2", "gpt-5.2-2025-12-11", "gpt-5.3-codex", "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano",
        "gpt-5.5", "gpt-5.6", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.6-cyber"
    ]

    private static let gpt41Models: Set<String> = [
        "gpt-4.1", "gpt-4.1-2025-04-14", "gpt-4.1-mini", "gpt-4.1-mini-2025-04-14",
        "gpt-4.1-nano", "gpt-4.1-nano-2025-04-14"
    ]

    private static let gpt4oModels: Set<String> = [
        "gpt-4o", "gpt-4o-2024-08-06", "gpt-4o-2024-11-20", "gpt-4o-mini", "gpt-4o-mini-2024-07-18"
    ]
}
