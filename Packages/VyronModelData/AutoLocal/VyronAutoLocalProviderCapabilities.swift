import VyronModelDomain

/// Capabilities supported by the Auto Local adapters without a discovery request.
/// These values do not alter the model settings editor or persisted connection settings.
public enum VyronAutoLocalProviderCapabilities {
    public static func candidateModel(
        for profile: ModelConnectionProfile,
        tools: VyronModelFeatureStatus
    ) -> LocalModel {
        var capabilities: [String] = []
        switch tools {
        case .available: capabilities.append(VyronAutoLocalCapability.tools.rawValue)
        case .unverified: capabilities.append(VyronAutoLocalCapability.pendingTools.rawValue)
        case .unavailable: break
        }
        if supportsImages(for: profile) { capabilities.append(VyronAutoLocalCapability.vision.rawValue) }
        return LocalModel(name: profile.selectedModel, size: 0, capabilities: capabilities)
    }

    public static func thinkingSupport(for profile: ModelConnectionProfile) -> VyronModelThinkingSupport {
        if VyronOpenAIResponsesRoute.matches(profile) {
            return .levels(VyronModelThinkingLevels(levels: [.low, .medium, .high]))
        }
        if VyronDeepSeekRoute.matches(profile) {
            return VyronDeepSeekRoute.thinkingSupport(for: profile.selectedModel)
        }
        return profile.kind == .ollama ? .unverified : .providerDefaultOnly
    }

    public static func supportsImages(for profile: ModelConnectionProfile) -> Bool {
        // Image support currently comes from discovered per-model capabilities, not provider identity.
        // A saved profile alone contains no vision evidence, even for an official provider.
        false
    }
}
