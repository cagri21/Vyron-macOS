import Foundation

struct VyronOpenAIModelPricing: Sendable {
    let tokens: VyronOpenAITokenPrices
    let longContextThreshold: Int?
    let serviceTiers: Set<String>

    func serviceMultiplier(_ tier: String?) -> Decimal? {
        guard let tier, tier != "default" else { return 1 }
        guard serviceTiers.contains(tier) else { return nil }
        switch tier {
        case "fast", "priority": return 2
        case "flex": return Decimal(1) / 2
        case "ultrafast": return 6
        default: return nil
        }
    }
}
