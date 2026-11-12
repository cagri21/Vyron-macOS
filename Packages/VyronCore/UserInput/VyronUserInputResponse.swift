import Foundation

public struct VyronUserInputResponse: Codable, Sendable, Equatable {
    public let requestID: UUID
    public let answers: [VyronUserInputAnswer]

    public init(requestID: UUID, answers: [VyronUserInputAnswer]) {
        self.requestID = requestID
        self.answers = answers
    }
}
