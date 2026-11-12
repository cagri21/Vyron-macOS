import Foundation
import VyronModelDomain

/// A billable inference attempt, independent of the chat or task that requested it.
public struct VyronOpenAIUsageEvent: Sendable, Equatable {
    public let connectionID: UUID
    public let requestID: UUID
    public let startedAt: Date
    public let observation: VyronOpenAIUsageObservation

    public init(
        connectionID: UUID,
        requestID: UUID,
        startedAt: Date,
        observation: VyronOpenAIUsageObservation
    ) {
        self.connectionID = connectionID
        self.requestID = requestID
        self.startedAt = startedAt
        self.observation = observation
    }
}
