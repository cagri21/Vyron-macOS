struct VyronAppearancePreferences: Codable, Equatable, Sendable {
    var mode = VyronAppearanceMode.dark
    var preset = VyronAppearancePreset.vyron
    var fontFamily: String?
    var customColors: [VyronAppearancePreset: VyronAppearanceVariants] = [:]
}
