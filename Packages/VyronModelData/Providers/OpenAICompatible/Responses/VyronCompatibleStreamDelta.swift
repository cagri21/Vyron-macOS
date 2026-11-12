import VyronModelDomain

struct VyronCompatibleStreamDelta: Decodable {
    let content: String?
    let reasoningContent: String?
}
