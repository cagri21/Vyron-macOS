import Foundation

public struct VyronUserInputRequest: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let questions: [VyronUserInputQuestion]

    public init(id: UUID = UUID(), questions: [VyronUserInputQuestion]) {
        self.id = id
        self.questions = questions
    }
}
