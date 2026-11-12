import Foundation
import VyronLocalization
import VyronModelDomain

struct VyronOpenAIResponsesTokenCount: Decodable {
    let object: String
    let inputTokens: Int

    func validated() throws -> Int {
        guard object == "response.input_tokens",
            (0...VyronOpenAIResponsesLimits.requestBytes).contains(inputTokens)
        else {
            throw ModelProviderError.invalidResponse(VyronModelDataText.invalidInputTokenCount)
        }
        return inputTokens
    }
}
