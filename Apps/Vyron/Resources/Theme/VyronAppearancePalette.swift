import SwiftUI

struct VyronAppearancePalette: Equatable, Sendable {
    static let `default` = VyronAppearancePreset.vyron.palette(for: .dark)

    let scheme: ColorScheme
    let preset: VyronAppearancePreset
    let overrides: VyronAppearanceColorOverrides
    private let seeds: VyronAppearanceSeedColors

    init(preset: VyronAppearancePreset, scheme: ColorScheme, overrides: VyronAppearanceColorOverrides) {
        let base = preset.seedColors(for: scheme)
        self.preset = preset
        self.scheme = scheme
        self.overrides = overrides
        seeds = VyronAppearanceSeedColors(
            background: overrides.background?.color ?? base.background,
            foreground: overrides.foreground?.color ?? base.foreground,
            accent: overrides.accent?.color ?? base.accent
        )
    }

    var background: Color { seeds.background }
    var foreground: Color { seeds.foreground }
    var controlAccent: Color { seeds.accent }
    var canvas: Color { background }
    var text: Color { foreground }
    var terminal: Color { background }
    var codeText: Color { foreground }

    var sidebar: Color {
        if usesLegacyBackground { return VyronColors.appearanceVyronDarkSidebar }
        if scheme == .dark { return mix(background, with: .black, amount: 0.17) }
        return mix(background, with: surfaceContrast, amount: 0.045)
    }

    var surface: Color {
        if usesLegacyBackground { return VyronColors.appearanceVyronDarkSurface }
        return mix(background, with: surfaceContrast, amount: 0.055)
    }

    var field: Color {
        if usesLegacyBackground { return VyronColors.appearanceVyronDarkField }
        return mix(background, with: surfaceContrast, amount: 0.095)
    }

    var raised: Color {
        if usesLegacyBackground { return VyronColors.appearanceVyronDarkRaised }
        return mix(background, with: surfaceContrast, amount: 0.14)
    }

    var border: Color {
        if usesLegacyForeground { return .white.opacity(0.084) }
        return surfaceContrast.opacity(0.15)
    }

    var selection: Color {
        if usesLegacyForeground, overrides.accent == nil { return .white.opacity(0.052) }
        return controlAccent.opacity(0.15)
    }

    var muted: Color {
        if usesLegacyForeground { return .white.opacity(0.498) }
        return mix(background, with: foreground, amount: 0.68)
    }

    var accent: Color {
        preset == .vyron && overrides.accent == nil ? foreground : controlAccent
    }

    var onAccent: Color {
        if usesLegacyForeground, overrides.accent == nil { return field }
        return VyronAppearanceColor(color: accent)?.contrastingText ?? background
    }

    var onControlAccent: Color {
        if usesLegacyColors { return foreground }
        return VyronAppearanceColor(color: controlAccent)?.contrastingText ?? background
    }

    var userMessageBackground: Color {
        if usesLegacyColors { return VyronColors.userMessageBackground }
        return mix(field, with: controlAccent, amount: 0.14)
    }

    var userMessageText: Color { usesLegacyColors ? VyronColors.userMessageText : foreground }
    var userMessageHint: Color { usesLegacyColors ? VyronColors.userMessageHint : muted }

    func color(for slot: VyronAppearanceColorSlot) -> Color {
        switch slot {
        case .accent: controlAccent
        case .background: background
        case .foreground: foreground
        case .success: success
        case .warning: warning
        case .danger: danger
        case .fullAccess: fullAccess
        }
    }

    private var usesLegacyBackground: Bool {
        preset == .vyron && scheme == .dark && overrides.background == nil
    }

    private var usesLegacyForeground: Bool {
        usesLegacyBackground && overrides.foreground == nil
    }

    private var usesLegacyColors: Bool {
        usesLegacyForeground && overrides.accent == nil
    }

    private var surfaceContrast: Color {
        VyronAppearanceColor(color: background)?.contrastingText ?? foreground
    }

    private func mix(_ color: Color, with tint: Color, amount: Double) -> Color {
        guard let source = VyronAppearanceColor(color: color), let target = VyronAppearanceColor(color: tint)
        else { return color }
        return source.mixed(with: target, amount: amount)
    }
}
