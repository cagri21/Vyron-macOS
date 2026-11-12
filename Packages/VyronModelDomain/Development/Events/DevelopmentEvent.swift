import Foundation

public struct DevelopmentEvent: Identifiable, Sendable {
    public let id = UUID()
    public let kind: Kind
    public let message: String
    public let tool: String?
    public let path: String?
    public let command: String?
    public let content: String?
    public let failure: String?

    public init(
        kind: Kind,
        message: String,
        tool: String? = nil,
        path: String? = nil,
        command: String? = nil,
        content: String? = nil,
        failure: String? = nil
    ) {
        self.kind = kind
        self.message = message
        self.tool = tool
        self.path = path
        self.command = command
        self.content = content
        self.failure = failure
    }
}
