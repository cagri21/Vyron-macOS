struct VyronAppearanceColorOverrides: Codable, Equatable, Sendable {
    var accent: VyronAppearanceColor?
    var background: VyronAppearanceColor?
    var foreground: VyronAppearanceColor?

    var isEmpty: Bool { accent == nil && background == nil && foreground == nil }

    subscript(slot: VyronAppearanceColorSlot) -> VyronAppearanceColor? {
        get {
            switch slot {
            case .accent: accent
            case .background: background
            case .foreground: foreground
            }
        }
        set {
            switch slot {
            case .accent: accent = newValue
            case .background: background = newValue
            case .foreground: foreground = newValue
            }
        }
    }
}
