import VyronModelDomain

struct VyronCompatibleStreamChoice: Decodable {
    let index: Int?
    let delta: VyronCompatibleStreamDelta?
    let finishReason: String?
}
