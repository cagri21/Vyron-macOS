import VyronModelDomain

extension VyronCompatibleStreamChoice {
    enum CodingKeys: String, CodingKey {
        case index, delta
        case finishReason = "finish_reason"
    }
}
