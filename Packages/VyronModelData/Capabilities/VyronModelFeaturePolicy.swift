import Foundation
import VyronModelDomain

/// Describes the selected model's capabilities in the adapters Vyron currently implements.
/// It performs no discovery, inference, or persistence and never infers support from a provider's brand.
public enum VyronModelFeaturePolicy {
    public static func assess(_ context: VyronModelFeatureContext) -> VyronModelFeatureReport {
        let selected = !context.model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let tools = toolAvailability(context, selected: selected)
        let thinking = thinkingAvailability(context, selected: selected)
        let builtin = context.connection == nil
        let features = VyronModelFeature.allCases.map { feature in
            switch feature {
            case .chat:
                return VyronModelFeatureAvailability(
                    feature: feature,
                    status: selected ? .available : .unverified,
                    reason: selected ? nil : .modelNotSelected
                )
            case .agent, .plan, .mcp:
                return VyronModelFeatureAvailability(feature: feature, status: tools.status, reason: tools.reason)
            case .thinking:
                return thinking
            case .mac, .browser:
                return VyronModelFeatureAvailability(
                    feature: feature,
                    status: builtin ? .available : .unavailable,
                    reason: builtin ? nil : .builtinConnectionRequired
                )
            }
        }
        return VyronModelFeatureReport(features: features)
    }

    private static func toolAvailability(
        _ context: VyronModelFeatureContext,
        selected: Bool
    ) -> VyronModelFeatureAvailability {
        guard selected else {
            return toolResult(.unverified, reason: .modelNotSelected)
        }
        let usesOllama = context.connection?.kind == .ollama || context.connection == nil
        let descriptor = usesOllama ? ModelCatalog.descriptor(for: context.model.name) : nil
        if descriptor?.role == .helper {
            return toolResult(.unavailable, reason: .helperModelReservedForChat)
        }
        switch context.toolVerification {
        case .verified:
            return toolResult(.available)
        case .unsupported:
            return toolResult(.unavailable, reason: .nativeToolsUnsupported)
        case .failed:
            return toolResult(.unverified, reason: .nativeToolVerificationFailed)
        case .unverified:
            break
        }
        if let capabilities = context.model.capabilities, !capabilities.isEmpty {
            if capabilities.contains("tools") {
                return toolResult(.available)
            }
            // Remote discovery is advisory: these adapters still run their native tool probes.
            if !usesOllama {
                return toolResult(.unverified, reason: .nativeToolsUnverified)
            }
            return toolResult(.unavailable, reason: .nativeToolsNotAdvertised)
        }
        if descriptor?.supportsTools == true {
            return toolResult(.available)
        }
        return toolResult(.unverified, reason: .nativeToolsUnverified)
    }

    private static func thinkingAvailability(
        _ context: VyronModelFeatureContext,
        selected: Bool
    ) -> VyronModelFeatureAvailability {
        if let connection = context.connection, VyronDeepSeekRoute.matches(connection) {
            let supported = VyronDeepSeekRoute.thinkingSupport(for: context.model.name) == .boolean
            return VyronModelFeatureAvailability(
                feature: .thinking,
                status: selected && supported ? .available : .unverified,
                reason: !selected ? .modelNotSelected : (supported ? nil : .thinkingUnverified)
            )
        }
        guard context.connection?.kind == .ollama || context.connection == nil else {
            return VyronModelFeatureAvailability(
                feature: .thinking,
                status: .unavailable,
                reason: .thinkingControlsUnsupportedByConnection
            )
        }
        guard selected else {
            return VyronModelFeatureAvailability(
                feature: .thinking,
                status: .unverified,
                reason: .modelNotSelected
            )
        }
        switch context.thinkingSupport {
        case .boolean:
            return VyronModelFeatureAvailability(feature: .thinking, status: .available)
        case .levels(let controls):
            return VyronModelFeatureAvailability(
                feature: .thinking,
                status: controls.hasControls ? .available : .unavailable,
                reason: controls.hasControls ? nil : .thinkingLevelsUnsupported
            )
        case .unsupported:
            return VyronModelFeatureAvailability(
                feature: .thinking,
                status: .unavailable,
                reason: .thinkingNotAdvertised
            )
        case .providerDefaultOnly:
            return VyronModelFeatureAvailability(
                feature: .thinking,
                status: .unavailable,
                reason: .thinkingLevelsUnsupported
            )
        case .unverified:
            break
        }
        let descriptor = ModelCatalog.descriptor(for: context.model.name)
        let supportsThinking =
            context.model.capabilities?.contains("thinking") == true
            || descriptor?.supportsThinking == true
        if supportsThinking {
            // Capability flags identify native reasoning, not the control values this model accepts.
            return VyronModelFeatureAvailability(
                feature: .thinking,
                status: .unverified,
                reason: .thinkingUnverified
            )
        }
        if context.model.capabilities != nil || descriptor != nil {
            return VyronModelFeatureAvailability(
                feature: .thinking,
                status: .unavailable,
                reason: .thinkingNotAdvertised
            )
        }
        return VyronModelFeatureAvailability(
            feature: .thinking,
            status: .unverified,
            reason: .thinkingUnverified
        )
    }

    private static func toolResult(
        _ status: VyronModelFeatureStatus,
        reason: VyronModelFeatureReason? = nil
    ) -> VyronModelFeatureAvailability {
        VyronModelFeatureAvailability(feature: .agent, status: status, reason: reason)
    }

}
