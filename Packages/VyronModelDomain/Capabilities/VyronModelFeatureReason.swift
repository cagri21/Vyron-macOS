public enum VyronModelFeatureReason: Equatable, Sendable {
    case modelNotSelected
    case nativeToolsNotAdvertised
    case nativeToolsUnverified
    case nativeToolVerificationFailed
    case nativeToolsUnsupported
    case chatAdapterIncompatible
    case helperModelReservedForChat
    case thinkingControlsUnsupportedByConnection
    case thinkingNotAdvertised
    case thinkingLevelsUnsupported
    case thinkingUnverified
    case builtinConnectionRequired
}
