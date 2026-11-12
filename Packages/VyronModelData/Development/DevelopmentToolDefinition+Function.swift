extension DevelopmentToolDefinition {
    struct Function: Encodable {
        let name: String
        let description: String
        let parameters: Parameters
    }
}
