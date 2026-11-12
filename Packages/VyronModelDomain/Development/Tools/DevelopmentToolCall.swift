import Foundation

public struct DevelopmentToolCall: Codable, Sendable, Equatable {
    public let function: Function
    public let id: String?
    public init(name: String, arguments: [String: DevelopmentJSONValue], id: String? = nil) {
        function = Function(name: name, arguments: arguments); self.id = id
    }
}
