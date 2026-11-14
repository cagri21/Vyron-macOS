import SwiftUI
import XCTest
@testable import Vyron

final class VyronAppearanceStatusColorTests: XCTestCase {
    func testCatppuccinUsesSeparateColorsForFailureAndFullAccess() throws {
        let palette = VyronAppearancePreset.catppuccin.palette(for: .dark)
        XCTAssertEqual(try rgb(palette.danger).hex, "#F38BA8")
        XCTAssertEqual(try rgb(palette.fullAccess).hex, "#FAB387")
        XCTAssertNotEqual(try rgb(palette.warning), try rgb(palette.fullAccess))
        XCTAssertNotEqual(try rgb(palette.danger), try rgb(VyronAppearancePalette.default.danger))
    }

    func testPresetStatusColorsAreReadableOnCanvasAndRaisedSurfaces() throws {
        let slots: [VyronAppearanceColorSlot] = [.success, .warning, .danger, .fullAccess]
        for preset in VyronAppearancePreset.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let palette = preset.palette(for: scheme)
                for background in [palette.canvas, palette.raised] {
                    let surface = try rgb(background)
                    for slot in slots {
                        let ratio = try rgb(palette.color(for: slot)).contrastRatio(over: surface)
                        XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(preset) \(scheme) \(slot) on \(surface.hex)")
                    }
                }
            }
        }
    }

    func testCustomBackgroundKeepsDefaultStatusReadableAndHonorsExplicitOverrides() throws {
        var overrides = VyronAppearanceColorOverrides()
        overrides[.background] = VyronAppearanceColor(hex: "#FFFFFF")
        let preset = VyronAppearancePreset.catppuccin
        let palette = preset.palette(for: .dark, overrides: overrides)
        XCTAssertGreaterThanOrEqual(try rgb(palette.danger).contrastRatio(over: rgb(palette.raised)), 4.5)

        overrides[.danger] = VyronAppearanceColor(hex: "#AA11CC")
        let customized = preset.palette(for: .dark, overrides: overrides)
        XCTAssertEqual(try rgb(customized.danger).hex, "#AA11CC")
        XCTAssertEqual(try rgb(customized.diffRemoved).hex, "#AA11CC")
    }

    private func rgb(_ color: Color) throws -> VyronAppearanceColor {
        try XCTUnwrap(VyronAppearanceColor(color: color))
    }
}
