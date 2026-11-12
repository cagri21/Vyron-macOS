extension DevelopmentStepResponse {
    enum CodingKeys: String, CodingKey {
        case message, done, error
        case doneReason = "done_reason"
    }
}
