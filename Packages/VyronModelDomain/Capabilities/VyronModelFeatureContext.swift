public struct VyronModelFeatureContext: Equatable, Sendable {
    /// A nil connection is Vyron's built-in Ollama connection on this Mac.
    public let connection: ModelConnectionProfile?
    public let model: LocalModel
    public let toolVerification: VyronNativeToolVerification
    public let thinkingSupport: VyronModelThinkingSupport

    public init(
        connection: ModelConnectionProfile? = nil,
        model: LocalModel,
        toolVerification: VyronNativeToolVerification = .unverified,
        thinkingSupport: VyronModelThinkingSupport = .unverified
    ) {
        self.connection = connection
        self.model = model
        self.toolVerification = toolVerification
        self.thinkingSupport = thinkingSupport
    }
}
