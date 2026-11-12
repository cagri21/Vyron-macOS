import VyronCore

enum VyronModelFeaturePresentation {
    static func title(_ feature: VyronModelFeature) -> String {
        switch feature {
        case .chat: VyronAppText.modelFeaturesChat
        case .agent: VyronAppText.modelFeaturesAgent
        case .plan: VyronAppText.modelFeaturesPlan
        case .mcp: VyronAppText.modelFeaturesPlugins
        case .thinking: VyronAppText.modelFeaturesThinking
        case .mac: VyronAppText.modelFeaturesMac
        case .browser: VyronAppText.modelFeaturesBrowser
        }
    }

    static func status(_ status: VyronModelFeatureStatus) -> String {
        switch status {
        case .available: VyronAppText.modelFeaturesAvailable
        case .unavailable: VyronAppText.modelFeaturesUnavailable
        case .unverified: VyronAppText.modelFeaturesUnverified
        }
    }

    static func reason(_ reason: VyronModelFeatureReason?) -> String? {
        switch reason {
        case nil: nil
        case .modelNotSelected: VyronAppText.modelFeaturesSelectModel
        case .nativeToolsNotAdvertised: VyronAppText.modelFeaturesNoTools
        case .nativeToolsUnverified: VyronAppText.modelFeaturesCheckTools
        case .nativeToolVerificationFailed: VyronAppText.modelFeaturesCheckFailed
        case .nativeToolsUnsupported: VyronAppText.modelFeaturesToolsUnsupported
        case .chatAdapterIncompatible: VyronAppText.modelFeaturesDeepSeek
        case .helperModelReservedForChat: VyronAppText.modelFeaturesHelper
        case .thinkingControlsUnsupportedByConnection: VyronAppText.modelFeaturesThinkingConnection
        case .thinkingNotAdvertised: VyronAppText.modelFeaturesNoThinking
        case .thinkingUnverified: VyronAppText.modelFeaturesCheckThinking
        case .thinkingLevelsUnsupported: VyronAppText.modelFeaturesThinkingLevelsUnsupported
        case .builtinConnectionRequired: VyronAppText.modelFeaturesBuiltin
        }
    }
}
