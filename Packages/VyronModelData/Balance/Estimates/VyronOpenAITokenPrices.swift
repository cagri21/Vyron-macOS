import Foundation

/// USD per million tokens. Input categories are mutually exclusive.
struct VyronOpenAITokenPrices: Sendable {
    let input: Decimal
    let cachedInput: Decimal
    let output: Decimal
    let cacheWrites: VyronOpenAICacheWritePrices?
}
