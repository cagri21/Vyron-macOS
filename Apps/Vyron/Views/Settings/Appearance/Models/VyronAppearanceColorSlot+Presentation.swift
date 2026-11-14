extension VyronAppearanceColorSlot {
    var title: String {
        switch self {
        case .accent: VyronAppearanceText.accent
        case .background: VyronAppearanceText.background
        case .foreground: VyronAppearanceText.foreground
        case .success: VyronAppearanceText.success
        case .warning: VyronAppearanceText.warning
        case .danger: VyronAppearanceText.error
        case .fullAccess: VyronWorkspaceText.fullAccess
        }
    }
}
