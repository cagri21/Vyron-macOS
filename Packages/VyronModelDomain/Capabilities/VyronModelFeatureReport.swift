public struct VyronModelFeatureReport: Equatable, Sendable {
    public let features: [VyronModelFeatureAvailability]

    public var unavailableFeatures: [VyronModelFeatureAvailability] {
        features.filter { $0.status == .unavailable }
    }

    public init(features: [VyronModelFeatureAvailability]) {
        self.features = features
    }

    public subscript(feature: VyronModelFeature) -> VyronModelFeatureAvailability {
        features.first { $0.feature == feature }
            ?? VyronModelFeatureAvailability(
                feature: feature,
                status: .unverified,
                reason: .modelNotSelected
            )
    }
}
