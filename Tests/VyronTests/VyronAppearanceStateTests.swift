import Foundation
import SwiftUI
import XCTest
@testable import Vyron

@MainActor
final class VyronAppearanceStateTests: XCTestCase {
    func testFirstRunPreservesVyronDarkAndPresetsProvideBothVariants() throws {
        try withDefaults { defaults in
            let state = VyronAppearanceState(defaults: defaults)
            XCTAssertTrue(state.isDefault)
            XCTAssertEqual(state.mode.preferredColorScheme, .dark)
            XCTAssertEqual(state.preset, .vyron)
            XCTAssertEqual(hex(state.palette(for: .dark).canvas), "#181818")
            XCTAssertEqual(hex(state.palette(for: .dark).text), "#DFDFDF")
            XCTAssertEqual(hex(state.palette(for: .dark).controlAccent), "#339CFF")
            state.setColor(VyronAppearanceColor(hex: "#181818"), for: .background, scheme: .dark)
            XCTAssertTrue(state.isDefault)
            XCTAssertEqual(hex(state.palette(for: .dark).surface), "#232323")

            state.setMode(.system)
            XCTAssertNil(state.mode.preferredColorScheme)
            for preset in VyronAppearancePreset.allCases {
                let light = preset.palette(for: .light)
                let dark = preset.palette(for: .dark)
                XCTAssertNotEqual(hex(light.background), hex(dark.background), "\(preset) background")
                XCTAssertNotEqual(hex(light.foreground), hex(dark.foreground), "\(preset) foreground")
            }

            state.selectPreset(.chatGPT)
            XCTAssertEqual(hex(state.palette(for: .dark).canvas), "#181818")
            XCTAssertEqual(hex(state.palette(for: .dark).text), "#FFFFFF")
            state.setMode(.light)
            XCTAssertEqual(state.mode.preferredColorScheme, .light)
        }
    }

    func testOverridesSurviveRelaunchAndStaySeparateByPresetAndScheme() throws {
        try withDefaults { defaults in
            let state = VyronAppearanceState(defaults: defaults)
            state.setMode(.system)
            state.setFontFamily("Menlo")
            state.selectPreset(.dracula)
            let originalDark = state.palette(for: .dark).controlAccent
            let originalLight = state.palette(for: .light).controlAccent
            let custom = try XCTUnwrap(VyronAppearanceColor(hex: "  #123abC  "))
            state.setColor(custom, for: .accent, scheme: .dark)
            state.selectPreset(.gitHub)
            XCTAssertFalse(state.hasColorOverride(for: .accent, scheme: .dark))

            let restored = VyronAppearanceState(defaults: defaults)
            XCTAssertEqual(restored.mode, .system)
            XCTAssertEqual(restored.preset, .gitHub)
            XCTAssertEqual(restored.fontFamily, "Menlo")
            restored.selectPreset(.dracula)
            XCTAssertEqual(hex(restored.palette(for: .dark).controlAccent), "#123ABC")
            XCTAssertEqual(restored.palette(for: .light).controlAccent, originalLight)
            restored.setColor(nil, for: .accent, scheme: .dark)
            XCTAssertEqual(restored.palette(for: .dark).controlAccent, originalDark)

            restored.reset()
            XCTAssertTrue(VyronAppearanceState(defaults: defaults).isDefault)
        }
    }

    func testShareRoundTripPreservesBothVariantsAndRejectsInvalidValuesAtomically() throws {
        try withDefaults { defaults in
            let source = VyronAppearanceState(defaults: defaults)
            source.selectPreset(.catppuccin)
            source.setFontFamily("Avenir Next")
            source.setColor(VyronAppearanceColor(hex: "#ABCDEF"), for: .background, scheme: .light)
            source.setColor(VyronAppearanceColor(hex: "#101820"), for: .background, scheme: .dark)
            let share = try XCTUnwrap(source.exportTheme())

            source.reset()
            source.setMode(.system)
            XCTAssertTrue(source.importTheme(share))
            XCTAssertEqual(source.mode, .system)
            XCTAssertEqual(source.preset, .catppuccin)
            XCTAssertEqual(source.fontFamily, "Avenir Next")
            XCTAssertEqual(hex(source.palette(for: .light).background), "#ABCDEF")
            XCTAssertEqual(hex(source.palette(for: .dark).background), "#101820")

            let unsupported = share.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")
            XCTAssertFalse(source.importTheme(unsupported))
            XCTAssertFalse(source.importTheme(share.replacingOccurrences(of: "#ABCDEF", with: "#bad-hex")))
            XCTAssertFalse(source.importTheme(share + String(repeating: " ", count: 4_096)))
            XCTAssertEqual(source.exportTheme(), share)
        }
    }

    func testStatusColorsPersistAndShareWithoutChangingOtherPresetsOrSchemes() throws {
        try withDefaults { defaults in
            let state = VyronAppearanceState(defaults: defaults)
            state.selectPreset(.catppuccin)
            let dark = state.palette(for: .dark)
            let light = state.palette(for: .light)
            state.setColor(VyronAppearanceColor(hex: "#FDBD6C"), for: .warning, scheme: .dark)
            state.setColor(VyronAppearanceColor(hex: "#F37982"), for: .danger, scheme: .dark)
            state.setColor(VyronAppearanceColor(hex: "#9FDBF4"), for: .fullAccess, scheme: .dark)
            state.setColor(VyronAppearanceColor(hex: "#117650"), for: .success, scheme: .light)
            let share = try XCTUnwrap(state.exportTheme())

            let restored = VyronAppearanceState(defaults: defaults)
            XCTAssertEqual(hex(restored.palette(for: .dark).warning), "#FDBD6C")
            XCTAssertEqual(hex(restored.palette(for: .dark).danger), "#F37982")
            XCTAssertEqual(hex(restored.palette(for: .dark).fullAccess), "#9FDBF4")
            XCTAssertEqual(hex(restored.palette(for: .light).success), "#117650")
            XCTAssertEqual(restored.palette(for: .dark).success, dark.success)
            XCTAssertEqual(restored.palette(for: .light).warning, light.warning)
            restored.selectPreset(.vyron)
            XCTAssertFalse(restored.hasColorOverride(for: .warning, scheme: .dark))

            restored.reset()
            XCTAssertTrue(restored.importTheme(share))
            XCTAssertEqual(restored.exportTheme(), share)
            restored.setColor(nil, for: .warning, scheme: .dark)
            XCTAssertFalse(restored.hasColorOverride(for: .warning, scheme: .dark))
            XCTAssertEqual(restored.palette(for: .dark).warning, dark.warning)
            XCTAssertEqual(hex(restored.palette(for: .dark).danger), "#F37982")
            restored.reset()
            XCTAssertTrue(VyronAppearanceState(defaults: defaults).isDefault)
        }
    }

    func testPreferencesAndSharesWithoutStatusOverridesStillLoad() throws {
        try withDefaults { defaults in
            let legacyPreferences = """
                {
                    "mode": "system",
                    "preset": "catppuccin",
                    "fontFamily": "Menlo",
                    "customColors": ["catppuccin", {"light": {}, "dark": {"background": "#101820"}}]
                }
                """
            defaults.set(Data(legacyPreferences.utf8), forKey: VyronUserDefaultsKey.appearancePreferences.rawValue)
            let state = VyronAppearanceState(defaults: defaults)
            XCTAssertEqual(state.mode, .system)
            XCTAssertEqual(state.preset, .catppuccin)
            XCTAssertEqual(state.fontFamily, "Menlo")
            XCTAssertEqual(hex(state.palette(for: .dark).background), "#101820")
            XCTAssertFalse(state.hasColorOverride(for: .fullAccess, scheme: .dark))

            let legacyShare = """
                {"version": 1, "preset": "codex", "colors": {"light": {"foreground": "#142335"}, "dark": {}}}
                """
            XCTAssertTrue(state.importTheme(legacyShare))
            XCTAssertEqual(state.mode, .system)
            XCTAssertEqual(state.preset, .codex)
            XCTAssertEqual(hex(state.palette(for: .light).foreground), "#142335")
            XCTAssertFalse(state.hasColorOverride(for: .danger, scheme: .light))
        }
    }

    func testHexValidationRejectsNonRGBInput() {
        XCTAssertNil(VyronAppearanceColor(hex: "#FFF"))
        XCTAssertNil(VyronAppearanceColor(hex: "#FFFFFFFF"))
        XCTAssertNil(VyronAppearanceColor(hex: "+12345"))
        XCTAssertNil(VyronAppearanceColor(hex: "#afgh12"))
    }

    private func hex(_ color: Color) -> String? {
        VyronAppearanceColor(color: color)?.hex
    }

    private func withDefaults(_ test: (UserDefaults) throws -> Void) throws {
        let name = "VyronAppearanceStateTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try test(defaults)
    }
}
