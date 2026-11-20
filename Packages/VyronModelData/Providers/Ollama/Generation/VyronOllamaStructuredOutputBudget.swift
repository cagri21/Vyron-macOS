import Foundation
import VyronLocalization
import VyronModelDomain

struct VyronOllamaStructuredOutputBudget {
    let outputTokens: Int
    let contextTokens: Int
    let inputBytes: Int

    static let reasoningOutputTokens = 4_096
    private static let requestOverheadTokens = 2_048

    func resolved(reasoningMayRun: Bool, maximumOutputTokens: Int?) throws -> Int {
        let desired = reasoningMayRun ? max(outputTokens, Self.reasoningOutputTokens) : outputTokens
        let remaining = contextTokens - inputBytes - Self.requestOverheadTokens
        guard remaining > 0 else {
            throw LocalAIError.invalidResponse(VyronModelDataText.structuredContextExceeded)
        }
        return min(desired, maximumOutputTokens ?? desired, remaining)
    }
}
