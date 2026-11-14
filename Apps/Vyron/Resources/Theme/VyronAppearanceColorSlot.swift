enum VyronAppearanceColorSlot: CaseIterable, Identifiable, Sendable {
    case accent
    case background
    case foreground
    case success
    case warning
    case danger
    case fullAccess

    var id: Self { self }
}
