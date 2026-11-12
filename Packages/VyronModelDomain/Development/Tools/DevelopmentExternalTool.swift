/// A native tool schema supplied by an explicitly connected integration.
public struct DevelopmentExternalTool: Sendable, Equatable {
    public let name: String
    public let description: String
    public let inputSchema: [String: DevelopmentJSONValue]
    public let isReadOnly: Bool

    public init(name: String, description: String, inputSchema: [String: DevelopmentJSONValue], isReadOnly: Bool) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.isReadOnly = isReadOnly
    }
}
