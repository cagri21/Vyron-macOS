public enum VyronModelFeatureStatus: Equatable, Sendable {
    case available
    case unavailable
    case unverified

    /// An unknown capability may still be checked by the existing provider path.
    public var isEnabled: Bool { self != .unavailable }
}
