struct VyronAppearanceColorOverrides: Codable, Equatable, Sendable {
    var accent: VyronAppearanceColor?
    var background: VyronAppearanceColor?
    var foreground: VyronAppearanceColor?
    private var status: VyronAppearanceStatusOverrides?

    var isEmpty: Bool {
        accent == nil && background == nil && foreground == nil && status?.isEmpty != false
    }

    subscript(slot: VyronAppearanceColorSlot) -> VyronAppearanceColor? {
        get {
            switch slot {
            case .accent: accent
            case .background: background
            case .foreground: foreground
            case .success: status?.success
            case .warning: status?.warning
            case .danger: status?.danger
            case .fullAccess: status?.fullAccess
            }
        }
        set {
            switch slot {
            case .accent: accent = newValue
            case .background: background = newValue
            case .foreground: foreground = newValue
            case .success: updateStatus(\.success, to: newValue)
            case .warning: updateStatus(\.warning, to: newValue)
            case .danger: updateStatus(\.danger, to: newValue)
            case .fullAccess: updateStatus(\.fullAccess, to: newValue)
            }
        }
    }

    private mutating func updateStatus(
        _ path: WritableKeyPath<VyronAppearanceStatusOverrides, VyronAppearanceColor?>,
        to color: VyronAppearanceColor?
    ) {
        var next = status ?? VyronAppearanceStatusOverrides()
        next[keyPath: path] = color
        status = next.isEmpty ? nil : next
    }
}
