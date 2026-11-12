extension DevelopmentToolCall {
    public struct Function: Codable, Sendable, Equatable {
        public let name: String
        public let arguments: [String: DevelopmentJSONValue]
        public init(name: String, arguments: [String: DevelopmentJSONValue]) {
            self.name = name; self.arguments = arguments
        }
    }
}
