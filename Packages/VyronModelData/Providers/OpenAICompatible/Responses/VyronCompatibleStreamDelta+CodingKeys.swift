import VyronModelDomain

extension VyronCompatibleStreamDelta {
    enum CodingKeys: String, CodingKey {
        case content
        case reasoningContent = "reasoning_content"
    }
}
