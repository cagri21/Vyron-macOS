import VyronModelDomain

public struct VyronOllamaInstalledModelIdentity: Sendable, Equatable {
    public let model: LocalModel
    public let digest: String

    public var name: String { model.name }
}
