import Foundation

/// A reviewed, offline price snapshot. Unknown IDs and billing tiers must remain unpriced.
/// Current families: https://developers.openai.com/api/docs/pricing
/// Legacy families: https://developers.openai.com/api/docs/models/<exact-model-id>
enum VyronOpenAIPriceCatalog {
    static func pricing(for model: String) -> VyronOpenAIModelPricing? {
        switch model {
        case "gpt-6-astra":
            return current(input: 10, cached: 1, output: 50, ultrafast: true)
        case "gpt-6.1-sol":
            return current(input: 2, cached: Decimal(1) / 10, output: 10, ultrafast: true)
        case "gpt-6-sol":
            return current(input: 2, cached: Decimal(1) / 5, output: 10)
        case "gpt-6.1-terra":
            return current(input: 1, cached: Decimal(1) / 20, output: 5)
        case "gpt-6-luna":
            return current(input: Decimal(1) / 10, cached: Decimal(1) / 100, output: Decimal(1) / 2)
        case "gpt-5.6-sol", "gpt-5.6":
            return VyronOpenAIModelPricing(
                tokens: writePrices(input: 4, cached: Decimal(2) / 5, output: 20),
                longContextThreshold: 272_000,
                serviceTiers: ["fast", "priority"]
            )
        case "gpt-5.6-cyber":
            return standard(writePrices(input: Decimal(25) / 2, cached: Decimal(5) / 4, output: 75))
        case "gpt-5.3-codex":
            return VyronOpenAIModelPricing(
                tokens: textPrices(input: Decimal(7) / 4, cached: Decimal(7) / 40, output: 14),
                longContextThreshold: nil,
                serviceTiers: ["fast", "priority"]
            )
        case "gpt-5", "gpt-5-2025-08-07", "gpt-5.1", "gpt-5.1-2025-11-13":
            return standard(textPrices(input: Decimal(5) / 4, cached: Decimal(1) / 8, output: 10))
        case "gpt-5-mini", "gpt-5-mini-2025-08-07":
            return standard(textPrices(input: Decimal(1) / 4, cached: Decimal(1) / 40, output: 2))
        case "gpt-5-nano", "gpt-5-nano-2025-08-07":
            return standard(textPrices(input: Decimal(1) / 20, cached: Decimal(1) / 200, output: Decimal(2) / 5))
        case "gpt-5.2", "gpt-5.2-2025-12-11":
            return standard(textPrices(input: Decimal(7) / 4, cached: Decimal(7) / 40, output: 14))
        case "gpt-4.1", "gpt-4.1-2025-04-14":
            return standard(textPrices(input: 2, cached: Decimal(1) / 2, output: 8))
        case "gpt-4.1-mini", "gpt-4.1-mini-2025-04-14":
            return standard(textPrices(input: Decimal(2) / 5, cached: Decimal(1) / 10, output: Decimal(8) / 5))
        case "gpt-4o", "gpt-4o-2024-08-06", "gpt-4o-2024-11-20":
            return standard(textPrices(input: Decimal(5) / 2, cached: Decimal(5) / 4, output: 10))
        case "gpt-4o-mini", "gpt-4o-mini-2024-07-18":
            return standard(textPrices(input: Decimal(3) / 20, cached: Decimal(3) / 40, output: Decimal(3) / 5))
        default:
            return nil
        }
    }

    private static func standard(_ prices: VyronOpenAITokenPrices) -> VyronOpenAIModelPricing {
        VyronOpenAIModelPricing(tokens: prices, longContextThreshold: nil, serviceTiers: [])
    }

    private static func current(
        input: Decimal,
        cached: Decimal,
        output: Decimal,
        ultrafast: Bool = false
    ) -> VyronOpenAIModelPricing {
        VyronOpenAIModelPricing(
            tokens: writePrices(input: input, cached: cached, output: output),
            longContextThreshold: 272_000,
            serviceTiers: ultrafast ? ["fast", "priority", "flex", "ultrafast"] : ["fast", "priority", "flex"]
        )
    }

    private static func textPrices(input: Decimal, cached: Decimal, output: Decimal) -> VyronOpenAITokenPrices {
        VyronOpenAITokenPrices(input: input, cachedInput: cached, output: output, cacheWrites: nil)
    }

    private static func writePrices(input: Decimal, cached: Decimal, output: Decimal) -> VyronOpenAITokenPrices {
        VyronOpenAITokenPrices(
            input: input,
            cachedInput: cached,
            output: output,
            cacheWrites: VyronOpenAICacheWritePrices(
                thirtyMinute: input * Decimal(5) / 4,
                twelveHour: input * Decimal(5) / 2
            )
        )
    }
}
