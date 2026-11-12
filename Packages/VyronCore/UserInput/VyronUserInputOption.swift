import Foundation

public struct VyronUserInputOption: Codable, Sendable, Equatable {
    public let label: String
    public let description: String

    public init(label: String, description: String) {
        self.label = label
        self.description = description
    }
}
