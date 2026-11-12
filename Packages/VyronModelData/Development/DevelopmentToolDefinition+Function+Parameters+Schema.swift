extension DevelopmentToolDefinition.Function.Parameters {
    struct Schema: Encodable {
        let type = "object"
        let properties: [String: Property]
        let required: [String]
        let additionalProperties = false
    }
}
