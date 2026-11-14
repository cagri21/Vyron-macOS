import AppKit
import SwiftUI
import XCTest
@testable import Vyron

@MainActor
final class VyronAppearanceSettingsRenderTests: XCTestCase {
    func testCaptureAppearanceSettingsInBothSchemes() throws {
        guard ProcessInfo.processInfo.environment["VYRON_CAPTURE_APPEARANCE_SETTINGS"] == "1" else {
            throw XCTSkip("Set VYRON_CAPTURE_APPEARANCE_SETTINGS=1 for the offscreen Appearance settings snapshots.")
        }
        let suite = "VyronAppearanceSettingsRenderTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let appearance = VyronAppearanceState(defaults: defaults)
        appearance.selectPreset(.chatGPT)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent(".build/verification/appearance", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try capture(.dark, width: VyronSettingsStyle.minimumContentWidth, appearance: appearance, directory: directory)
        try capture(.light, width: VyronSettingsStyle.contentWidth, appearance: appearance, directory: directory)
        try captureStatusColors(appearance: appearance, directory: directory)
    }

    private func capture(
        _ mode: VyronAppearanceMode,
        width: CGFloat,
        appearance: VyronAppearanceState,
        directory: URL
    ) throws {
        appearance.setMode(mode)
        let scheme = try XCTUnwrap(mode.preferredColorScheme)
        let palette = appearance.palette(for: scheme)
        let renderer = ImageRenderer(content: VStack(alignment: .leading, spacing: VyronSettingsStyle.sectionSpacing) {
            Text(VyronAppearanceText.title)
                .font(VyronSettingsStyle.title)
                .foregroundStyle(palette.text)
            VyronAppearanceSettingsView()
        }
        .padding(VyronSettingsStyle.contentPadding)
        .frame(width: width, alignment: .leading)
        .background(palette.canvas)
        .environment(appearance)
        .environment(\.vyronPalette, palette)
        .environment(\.colorScheme, scheme))
        try writeSnapshot(renderer, width: width, to: directory.appendingPathComponent(mode.rawValue + ".png"))
    }

    private func captureStatusColors(appearance: VyronAppearanceState, directory: URL) throws {
        appearance.selectPreset(.catppuccin)
        appearance.setMode(.dark)
        let palette = appearance.palette(for: .dark)
        let width = VyronSettingsStyle.minimumContentWidth
        let renderer = ImageRenderer(content: VyronAppearanceStatusColorsView()
            .padding(VyronSettingsStyle.contentPadding)
            .frame(width: width, alignment: .leading)
            .background(palette.canvas)
            .environment(appearance)
            .environment(\.vyronPalette, palette)
            .environment(\.colorScheme, .dark))
        try writeSnapshot(renderer, width: width, to: directory.appendingPathComponent("status-colors.png"))
    }

    private func writeSnapshot<Content: View>(
        _ renderer: ImageRenderer<Content>,
        width: CGFloat,
        to url: URL
    ) throws {
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            throw XCTSkip("BLOCKED: Offscreen Appearance settings rendering is unavailable.")
        }
        XCTAssertEqual(image.width, Int(width * renderer.scale))
        XCTAssertLessThan(image.height, Int(VyronSettingsStyle.minimumHeight * renderer.scale))
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: url, options: .atomic)
    }
}
