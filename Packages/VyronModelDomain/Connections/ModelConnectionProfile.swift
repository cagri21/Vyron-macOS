import Foundation

public struct ModelConnectionProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: ModelProviderKind
    public var endpoint: String
    public var selectedModel: String
    public var settings: ModelSettings

    public init(
        id: UUID = UUID(),
        name: String,
        kind: ModelProviderKind,
        endpoint: String,
        selectedModel: String = "",
        settings: ModelSettings = ModelSettings()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.endpoint = endpoint
        self.selectedModel = selectedModel
        self.settings = settings
    }
}
