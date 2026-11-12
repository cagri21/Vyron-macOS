import Foundation

public struct VyronSubagentIdentity: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let prompt: String
    public let model: String

    public init(id: UUID = UUID(), name: String, prompt: String, model: String) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.model = model
    }
}
