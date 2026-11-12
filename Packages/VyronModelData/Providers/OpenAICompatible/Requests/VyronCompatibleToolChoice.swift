import VyronModelDomain

struct VyronCompatibleToolChoice: Encodable {
    let type = "function"
    let function: VyronCompatibleToolSelection
}
