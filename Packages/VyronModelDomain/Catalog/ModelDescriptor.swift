import Foundation

public struct ModelDescriptor: Identifiable, Sendable, Hashable {
    private let identity: VyronCatalogModelIdentity
    private let guidance: VyronCatalogModelGuidance
    private let selection: VyronCatalogModelSelection
    public let supportsThinking: Bool

    public var id: String { tag }
    public var tag: String { identity.tag }
    public var displayName: String { identity.displayName }
    public var downloadSizeGB: Double { identity.downloadSizeGB }
    public var documentationURL: URL { identity.documentationURL }
    public var role: ModelRole { selection.role }
    public var summary: String { guidance.summary }
    public var memoryNote: String { guidance.memoryNote }
    public var supportsTools: Bool { true }
    public var isAutomaticCodingCandidate: Bool { selection.isAutomaticCodingCandidate }
    public var automaticPriority: Int { selection.automaticPriority }
    public var recommendedContextTokens: Int { selection.recommendedContextTokens }

    init(
        identity: VyronCatalogModelIdentity,
        guidance: VyronCatalogModelGuidance,
        selection: VyronCatalogModelSelection,
        supportsThinking: Bool
    ) {
        self.identity = identity
        self.guidance = guidance
        self.selection = selection
        self.supportsThinking = supportsThinking
    }
}
