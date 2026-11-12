extension AssistantRouteSchema {
    struct Property: Encodable {
        let type: [String]
        let `enum`: [String]?
        let maxLength: Int?
    }
}
