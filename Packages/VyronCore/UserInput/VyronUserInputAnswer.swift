import Foundation

public struct VyronUserInputAnswer: Codable, Sendable, Equatable {
    public let questionID: String
    public let value: String

    public init(questionID: String, value: String) {
        self.questionID = questionID
        self.value = value
    }
}
