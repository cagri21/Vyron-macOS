struct VyronAppearanceStatusOverrides: Codable, Equatable, Sendable {
    var success: VyronAppearanceColor?
    var warning: VyronAppearanceColor?
    var danger: VyronAppearanceColor?
    var fullAccess: VyronAppearanceColor?

    var isEmpty: Bool { success == nil && warning == nil && danger == nil && fullAccess == nil }
}
