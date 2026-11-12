import Foundation

public enum VyronOpenAICostEstimator {
    public static let verifiedOn = "2026-11-04"
    public static let pricingURL = URL(string: "https://developers.openai.com/api/docs/pricing")
    private static let tokensPerMillion = Decimal(1_000_000)

    public static func supports(model: String) -> Bool { VyronOpenAIPriceCatalog.pricing(for: model) != nil }

    /// Returns a USD estimate from provider-reported usage; nil means the request cannot be priced safely.
    public static func cost(for observation: VyronOpenAIUsageObservation) -> Decimal? {
        guard case .measured(let usage) = observation.result,
            let pricing = VyronOpenAIPriceCatalog.pricing(for: observation.model),
            let tierMultiplier = pricing.serviceMultiplier(observation.serviceTier),
            let ordinaryInput = ordinaryInputTokens(usage)
        else { return nil }
        let details = usage.inputDetails
        let prices = pricing.tokens
        var inputCost =
            Decimal(ordinaryInput) * prices.input
            + Decimal(details.cachedTokens) * prices.cachedInput
        if details.cacheWrite30mTokens > 0 || details.cacheWrite12hTokens > 0 {
            guard let writes = prices.cacheWrites else { return nil }
            inputCost +=
                Decimal(details.cacheWrite30mTokens) * writes.thirtyMinute
                + Decimal(details.cacheWrite12hTokens) * writes.twelveHour
        }
        var outputCost = Decimal(usage.outputTokens) * prices.output
        if let threshold = pricing.longContextThreshold, usage.inputTokens > threshold {
            inputCost *= 2
            outputCost *= Decimal(3) / 2
        }
        let result = (inputCost + outputCost) * tierMultiplier / tokensPerMillion
        return result.isNaN || result < 0 ? nil : result
    }

    private static func ordinaryInputTokens(_ usage: VyronOpenAITokenUsage) -> Int? {
        let details = usage.inputDetails
        guard usage.inputTokens >= 0, usage.outputTokens >= 0,
            details.cachedTokens >= 0, details.cacheWrite30mTokens >= 0, details.cacheWrite12hTokens >= 0,
            details.cachedTokens <= usage.inputTokens
        else { return nil }
        var ordinary = usage.inputTokens - details.cachedTokens
        guard details.cacheWrite30mTokens <= ordinary else { return nil }
        ordinary -= details.cacheWrite30mTokens
        guard details.cacheWrite12hTokens <= ordinary else { return nil }
        return ordinary - details.cacheWrite12hTokens
    }
}
