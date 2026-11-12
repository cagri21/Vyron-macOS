import Foundation
import VyronModelDomain

public struct VyronOpenAIUsageObservation: Sendable, Equatable {
    public let responseID: String?
    public let model: String
    public let serviceTier: String?
    public let result: VyronOpenAIUsageResult

    public init(responseID: String?, model: String, serviceTier: String?, result: VyronOpenAIUsageResult) {
        self.responseID = responseID
        self.model = model
        self.serviceTier = serviceTier
        self.result = result
    }
}
