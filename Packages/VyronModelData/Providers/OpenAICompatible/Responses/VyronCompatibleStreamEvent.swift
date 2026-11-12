import VyronModelDomain

struct VyronCompatibleStreamEvent: Decodable {
    let choices: [VyronCompatibleStreamChoice]?
    let error: DevelopmentJSONValue?
}
