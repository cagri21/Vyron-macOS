package struct VyronClarificationAnswer: Codable, Sendable, Equatable {
    package let question: String
    package let answer: String

    package init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
}
