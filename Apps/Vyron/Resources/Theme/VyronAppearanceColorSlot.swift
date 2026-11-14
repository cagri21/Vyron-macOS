enum VyronAppearanceColorSlot: CaseIterable, Identifiable, Sendable {
    case accent
    case background
    case foreground

    var id: Self { self }
}
