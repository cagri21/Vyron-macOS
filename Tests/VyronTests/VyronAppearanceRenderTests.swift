import AppKit
import SwiftUI
import XCTest
@testable import Vyron

@MainActor
final class VyronAppearanceRenderTests: XCTestCase {
    func testSidebarSelectionUsesThePaletteInjectedByItsWindow() throws {
        let light = VyronAppearancePreset.ayu.palette(for: .light)
        let dark = VyronAppearancePreset.ayu.palette(for: .dark)

        let lightPixel = try renderedSelectionPixel(palette: light)
        let darkPixel = try renderedSelectionPixel(palette: dark)

        XCTAssertGreaterThan(lightPixel.redComponent, darkPixel.redComponent + 0.4)
    }

    private func renderedSelectionPixel(palette: VyronAppearancePalette) throws -> NSColor {
        let renderer = ImageRenderer(
            content: HStack(spacing: 0) {
                Color.clear
                    .frame(width: 40, height: 40)
                    .modifier(VyronSidebarRowBackground(isSelected: true))
                palette.raised.frame(width: 40, height: 40)
            }
            .environment(\.vyronPalette, palette)
        )
        guard let image = renderer.cgImage else {
            throw XCTSkip("Offscreen SwiftUI rendering is unavailable.")
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        let y = bitmap.pixelsHigh / 2
        let selection = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 4, y: y))
        let reference = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide * 3 / 4, y: y))
        let pixel = try XCTUnwrap(selection.usingColorSpace(.sRGB))
        let expected = try XCTUnwrap(reference.usingColorSpace(.sRGB))
        XCTAssertEqual(pixel.redComponent, expected.redComponent, accuracy: 0.02)
        XCTAssertEqual(pixel.greenComponent, expected.greenComponent, accuracy: 0.02)
        XCTAssertEqual(pixel.blueComponent, expected.blueComponent, accuracy: 0.02)
        XCTAssertEqual(pixel.alphaComponent, 1, accuracy: 0.02)
        return pixel
    }
}
