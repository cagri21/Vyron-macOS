import VyronModelDomain

extension VyronAnthropicModelPage {
    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case lastID = "last_id"
    }
}
