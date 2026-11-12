import VyronModelDomain

struct VyronCompatibleCompletionChoice: Decodable {
    let message: VyronCompatibleMessage
    let finishReason: String?
}
