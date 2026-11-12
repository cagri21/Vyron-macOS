public struct VyronModelFeatureAvailability: Equatable, Identifiable, Sendable {
    public var id: VyronModelFeature { feature }
    public let feature: VyronModelFeature
    public let status: VyronModelFeatureStatus
    public let reason: VyronModelFeatureReason?

    public var isAvailable: Bool { status == .available }
    public var isEnabled: Bool { status.isEnabled }

    public init(
        feature: VyronModelFeature,
        status: VyronModelFeatureStatus,
        reason: VyronModelFeatureReason? = nil
    ) {
        self.feature = feature
        self.status = status
        self.reason = reason
    }
}
