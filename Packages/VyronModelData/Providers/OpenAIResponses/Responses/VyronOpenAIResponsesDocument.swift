import Foundation
import VyronLocalization
import VyronModelDomain

struct VyronOpenAIResponsesDocument: Decodable {
    let status: String
    let output: [DevelopmentJSONValue]
    let error: DevelopmentJSONValue?
    let incompleteDetails: DevelopmentJSONValue?

    func completedOutput() throws -> [DevelopmentJSONValue] {
        guard error == nil || error == .null else {
            throw ModelProviderError.invalidResponse(VyronModelDataText.modelIncompleteResponse)
        }
        if status == "incomplete", case .object(let details) = incompleteDetails {
            if details["reason"] == .string("max_output_tokens") {
                throw ModelProviderError.outputLimitReached
            }
            if details["reason"] == .string("content_filter") {
                throw ModelProviderError.invalidResponse(
                    VyronModelDataText.modelBlockedByContentFilter
                )
            }
        }
        guard status == "completed" else {
            throw ModelProviderError.invalidResponse(VyronModelDataText.modelIncompleteResponse)
        }
        return output
    }
}
