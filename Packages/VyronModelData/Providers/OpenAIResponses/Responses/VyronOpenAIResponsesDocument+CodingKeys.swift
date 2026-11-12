import VyronModelDomain

extension VyronOpenAIResponsesDocument {
    enum CodingKeys: String, CodingKey {
        case status, output, error
        case incompleteDetails = "incomplete_details"
    }
}
