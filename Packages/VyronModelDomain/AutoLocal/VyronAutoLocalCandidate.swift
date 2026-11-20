/// The opaque identifier belongs to the caller; an assessment cannot create a new connection or model.
public struct VyronAutoLocalCandidate: Sendable, Equatable {
    public let id: String
    public let model: LocalModel
    public let location: VyronAutoLocalLocation
    public let thinkingSupport: VyronModelThinkingSupport

    public init(
        id: String,
        model: LocalModel,
        location: VyronAutoLocalLocation,
        thinkingSupport: VyronModelThinkingSupport
    ) {
        self.id = id
        self.model = model
        self.location = location
        self.thinkingSupport = thinkingSupport
    }
}
