import VyronModelDomain

struct VyronAnthropicModelPage: Decodable {
    let data: [VyronAnthropicModelDescriptor]
    let hasMore: Bool
    let lastID: String?
}
