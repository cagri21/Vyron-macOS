import Foundation
import VyronModelDomain

struct VyronOpenAIResponsesGeneration {
    let maximumOutputTokens: Int
    let stream: Bool
    let reasoningEffort: String?

    init(maximumOutputTokens: Int, stream: Bool, reasoningEffort: String? = nil) {
        self.maximumOutputTokens = maximumOutputTokens
        self.stream = stream
        self.reasoningEffort = reasoningEffort
    }
}
