import SwiftUI

extension VyronAppearancePalette {
    var success: Color {
        statusColor(.success, fallback: statusSeeds.success)
    }

    var warning: Color {
        statusColor(.warning, fallback: statusSeeds.warning)
    }

    var danger: Color {
        statusColor(.danger, fallback: statusSeeds.danger)
    }

    var fullAccess: Color {
        statusColor(.fullAccess, fallback: statusSeeds.fullAccess)
    }

    var diffAdded: Color {
        guard usesDefaultDiffColors, overrides[.success] == nil else { return success }
        return legible(scheme == .dark ? VyronColors.appearanceDarkDiffAdded : VyronColors.appearanceLightDiffAdded)
    }

    var diffRemoved: Color {
        guard usesDefaultDiffColors, overrides[.danger] == nil else { return danger }
        return legible(scheme == .dark ? VyronColors.appearanceDarkDiffRemoved : VyronColors.appearanceLightDiffRemoved)
    }

    var diffHunk: Color {
        guard usesDefaultDiffColors, overrides.accent == nil else { return legible(controlAccent) }
        return legible(scheme == .dark ? VyronColors.appearanceDarkDiffHunk : VyronColors.appearanceLightDiffHunk)
    }

    private var statusSeeds: VyronAppearanceStatusColors { preset.statusColors(for: scheme) }

    private var usesDefaultDiffColors: Bool { preset == .vyron || preset == .codex }

    private func statusColor(_ slot: VyronAppearanceColorSlot, fallback: Color) -> Color {
        overrides[slot]?.color ?? legible(fallback)
    }

    private func legible(_ color: Color) -> Color {
        // Status labels also appear on selected sidebar rows and elevated controls.
        guard let ink = VyronAppearanceColor(color: color), let surface = VyronAppearanceColor(color: raised)
        else { return color }
        return ink.legible(over: surface)
    }
}
