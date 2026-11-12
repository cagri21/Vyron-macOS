import Foundation

public struct VyronUserInputQuestion: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let question: String
    public let options: [VyronUserInputOption]

    public init(id: String, question: String, options: [VyronUserInputOption] = []) {
        self.id = id
        self.question = question
        self.options = options
    }
}
