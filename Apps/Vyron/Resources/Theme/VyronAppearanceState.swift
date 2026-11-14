import Foundation
import Observation
import OSLog
import SwiftUI

@MainActor
@Observable
final class VyronAppearanceState {
    private static let logger = Logger(subsystem: "ai.vyron.desktop", category: "Appearance preferences")
    @ObservationIgnored private let defaults: UserDefaults
    private var preferences: VyronAppearancePreferences

    init(defaults: UserDefaults) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: VyronUserDefaultsKey.appearancePreferences.rawValue) else {
            preferences = VyronAppearancePreferences()
            return
        }
        do {
            preferences = try JSONDecoder().decode(VyronAppearancePreferences.self, from: data)
        } catch {
            Self.logger.error("Could not load saved appearance preferences. Using defaults.")
            preferences = VyronAppearancePreferences()
        }
    }

    var mode: VyronAppearanceMode { preferences.mode }
    var preset: VyronAppearancePreset { preferences.preset }
    var fontFamily: String? { preferences.fontFamily }
    var isDefault: Bool { preferences == VyronAppearancePreferences() }

    func setMode(_ mode: VyronAppearanceMode) {
        update { $0.mode = mode }
    }

    func selectPreset(_ preset: VyronAppearancePreset) {
        update { $0.preset = preset }
    }

    func setFontFamily(_ fontFamily: String?) {
        let trimmed = fontFamily?.trimmingCharacters(in: .whitespacesAndNewlines)
        update { $0.fontFamily = trimmed?.isEmpty == false ? trimmed : nil }
    }

    func setColor(_ color: VyronAppearanceColor?, for slot: VyronAppearanceColorSlot, scheme: ColorScheme) {
        let themeColor = VyronAppearanceColor(color: preset.palette(for: scheme).color(for: slot))
        let customColor = color == themeColor ? nil : color
        update { preferences in
            var variants = preferences.customColors[preferences.preset, default: VyronAppearanceVariants()]
            variants[scheme][slot] = customColor
            preferences.customColors[preferences.preset] = variants.isEmpty ? nil : variants
        }
    }

    func hasColorOverride(for slot: VyronAppearanceColorSlot, scheme: ColorScheme) -> Bool {
        colorOverrides(for: scheme)[slot] != nil
    }

    func palette(for scheme: ColorScheme) -> VyronAppearancePalette {
        preset.palette(for: scheme, overrides: colorOverrides(for: scheme))
    }

    func reset() {
        update { $0 = VyronAppearancePreferences() }
    }

    func exportTheme() -> String? {
        let share = VyronAppearanceShare(
            version: VyronAppearanceShare.currentVersion,
            preset: preset,
            colors: preferences.customColors[preset, default: VyronAppearanceVariants()],
            fontFamily: fontFamily
        )
        guard share.isSupported else { return nil }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(share)
            return String(decoding: data, as: UTF8.self)
        } catch {
            Self.logger.error("Could not encode appearance theme for sharing.")
            return nil
        }
    }

    func importTheme(_ string: String) -> Bool {
        guard string.utf8.prefix(VyronAppearanceShare.maximumBytes + 1).count <= VyronAppearanceShare.maximumBytes
        else { return false }
        do {
            let share = try JSONDecoder().decode(VyronAppearanceShare.self, from: Data(string.utf8))
            guard share.isSupported else { return false }
            return update { preferences in
                preferences.preset = share.preset
                preferences.fontFamily = share.fontFamily
                preferences.customColors[share.preset] = share.colors.isEmpty ? nil : share.colors
            }
        } catch {
            return false
        }
    }

    private func colorOverrides(for scheme: ColorScheme) -> VyronAppearanceColorOverrides {
        preferences.customColors[preferences.preset]?[scheme] ?? VyronAppearanceColorOverrides()
    }

    @discardableResult
    private func update(_ transform: (inout VyronAppearancePreferences) -> Void) -> Bool {
        var next = preferences
        transform(&next)
        guard next != preferences else { return true }
        do {
            let encoded = try JSONEncoder().encode(next)
            defaults.set(encoded, forKey: VyronUserDefaultsKey.appearancePreferences.rawValue)
            preferences = next
            return true
        } catch {
            Self.logger.error("Could not save appearance preferences.")
            return false
        }
    }
}
