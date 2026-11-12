import VyronModelDomain

extension VyronCompatibleCompletionChoice {
    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}
