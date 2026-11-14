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
