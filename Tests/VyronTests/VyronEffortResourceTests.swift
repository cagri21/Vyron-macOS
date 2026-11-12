import AppKit
import SwiftUI
import XCTest
@testable import Vyron

@MainActor
final class VyronEffortResourceTests: XCTestCase {
    func testEveryEffortAssetResolvesFromTheSwiftPackageResourceBundle() throws {
        for name in [
            "EffortAccent", "EffortTrackStart", "EffortTrackMiddle", "EffortTrackEnd",
            "EffortTrackInactive", "EffortSparkle"
        ] {
            let color = try VyronColorAssets.load(named: name)
            let resolved = try XCTUnwrap(NSColor(color).usingColorSpace(.sRGB))
            XCTAssertEqual(resolved.alphaComponent, 1, accuracy: 0.001, name)
        }
        let start = try XCTUnwrap(NSColor(Palette.effortTrackStart).usingColorSpace(.sRGB))
        XCTAssertGreaterThan(start.blueComponent, start.redComponent)
        let end = try XCTUnwrap(NSColor(Palette.effortTrackEnd).usingColorSpace(.sRGB))
        XCTAssertGreaterThan(end.redComponent, start.redComponent)
    }

    func testPaletteMatchesTheSuppliedPurpleReferenceInsteadOfErrorRed() throws {
        let expected: [(String, [CGFloat])] = [
            ("EffortAccent", [173, 123, 249]), ("EffortTrackStart", [51, 68, 189]),
            ("EffortTrackMiddle", [169, 133, 255]), ("EffortTrackEnd", [125, 99, 222]),
            ("EffortTrackInactive", [48, 48, 48]), ("EffortSparkle", [255, 255, 255])
        ]
        for (name, components) in expected {
            let color = try XCTUnwrap(NSColor(VyronColorAssets.load(named: name)).usingColorSpace(.sRGB))
            XCTAssertEqual(color.redComponent, components[0] / 255, accuracy: 0.00001, name)
            XCTAssertEqual(color.greenComponent, components[1] / 255, accuracy: 0.00001, name)
            XCTAssertEqual(color.blueComponent, components[2] / 255, accuracy: 0.00001, name)
            XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.00001, name)
        }
    }

    func testMissingAndUnsafeResourceNamesThrow() {
        for name in ["", "../EffortAccent", "EffortAccent/Contents", "MissingColor"] {
            XCTAssertThrowsError(try VyronColorAssets.load(named: name), name)
        }
    }

    func testMalformedNonfiniteAndOutOfRangeColorComponentsThrow() {
        for value in ["NaN", "Infinity", "nonsense", "-0.1", "1.1"] {
            let components = VyronColorAssetComponents(red: value, green: "1", blue: "1", alpha: "1")
            XCTAssertThrowsError(try components.resolved(), value)
        }
    }
}
