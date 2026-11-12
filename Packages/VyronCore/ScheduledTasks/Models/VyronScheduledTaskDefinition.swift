import Foundation

public struct VyronScheduledTaskDefinition: Codable, Equatable, Sendable {
    public var title: String
    public var prompt: String
    public var context: VyronScheduledTaskContext

    public init(title: String, prompt: String, context: VyronScheduledTaskContext) {
        self.title = title
        self.prompt = prompt
        self.context = context
    }
}
