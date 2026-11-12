import AppKit
import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronPackagedColorResourceTests: XCTestCase {
    func testFlatSwiftPMCatalogLoadsEvenWhenMacOSMetadataRedirectsFoundationLookup() throws {
        let bundle = try fixture(nestedResources: false)
        XCTAssertTrue(try XCTUnwrap(bundle.resourceURL).path.hasSuffix("Contents/Resources"))
        XCTAssertNil(bundle.url(
            forResource: "Contents", withExtension: "json", subdirectory: "Theme.xcassets/EffortAccent.colorset"
        ))
        try assertReferenceColors(in: bundle)
    }

    func testNativeMacOSBundleResourceLayoutLoadsTheSameReferenceColors() throws {
        let bundle = try fixture(nestedResources: true)
        XCTAssertNotNil(bundle.url(
            forResource: "Contents", withExtension: "json", subdirectory: "Theme.xcassets/EffortAccent.colorset"
        ))
        try assertReferenceColors(in: bundle)
    }

    func testMalformedPackagedColorRemainsAnExplicitLoadError() throws {
        let bundle = try fixture(nestedResources: false)
        let file = bundle.bundleURL.appendingPathComponent("Theme.xcassets/EffortAccent.colorset/Contents.json")
        try Data("broken color data".utf8).write(to: file)
        XCTAssertThrowsError(try VyronColorAssets.load(named: "EffortAccent", in: bundle))
        XCTAssertThrowsError(try VyronColorAssets.load(named: "MissingColor", in: bundle))
    }

    private func fixture(nestedResources: Bool) throws -> Bundle {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronPackagedColors-" + UUID().uuidString, isDirectory: true)
        let bundleURL = directory.appendingPathComponent("VyronResources.bundle", isDirectory: true)
        let contents = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let info: [String: String] = [
            "CFBundleIdentifier": "ai.vyron.test.colors." + UUID().uuidString,
            "CFBundleName": "VyronResources", "CFBundlePackageType": "BNDL", "CFBundleVersion": "1"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        let resourceURL = nestedResources ? contents.appendingPathComponent("Resources", isDirectory: true) : bundleURL
        try FileManager.default.createDirectory(at: resourceURL, withIntermediateDirectories: true)
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Apps/Vyron/Resources/Theme.xcassets")
        try FileManager.default.copyItem(at: source, to: resourceURL.appendingPathComponent("Theme.xcassets"))
        return try XCTUnwrap(Bundle(url: bundleURL))
    }

    private func assertReferenceColors(in bundle: Bundle) throws {
        let accent = try XCTUnwrap(NSColor(
            VyronColorAssets.load(named: "EffortAccent", in: bundle)
        ).usingColorSpace(.sRGB))
        XCTAssertEqual(accent.redComponent, 173.0 / 255, accuracy: 0.00001)
        XCTAssertEqual(accent.greenComponent, 123.0 / 255, accuracy: 0.00001)
        XCTAssertEqual(accent.blueComponent, 249.0 / 255, accuracy: 0.00001)
        let thumb = try XCTUnwrap(NSColor(
            VyronColorAssets.load(named: "EffortSparkle", in: bundle)
        ).usingColorSpace(.sRGB))
        XCTAssertEqual(thumb.redComponent, 1, accuracy: 0.00001)
        XCTAssertEqual(thumb.greenComponent, 1, accuracy: 0.00001)
        XCTAssertEqual(thumb.blueComponent, 1, accuracy: 0.00001)
    }
}
