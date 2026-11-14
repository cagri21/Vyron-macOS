extension VyronAppearanceColorSlot {
    var title: String {
        switch self {
        case .accent: VyronAppearanceText.accent
        case .background: VyronAppearanceText.background
        case .foreground: VyronAppearanceText.foreground
        }
    }
}
