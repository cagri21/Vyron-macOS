import AppKit
import SwiftUI
import XCTest
import VyronCore
@testable import Vyron

/// Offscreen snapshots only; no window, running app, credential lookup, or provider request.
@MainActor
final class VyronInferenceControlVisualTests: XCTestCase {
    func testCaptureActualSelectionLabelAndEffortPopover() throws {
        guard ProcessInfo.processInfo.environment["VYRON_CAPTURE_INFERENCE_SELECTOR"] == "1" else {
            throw XCTSkip("Set VYRON_CAPTURE_INFERENCE_SELECTOR=1 to capture the real controls offscreen.")
        }
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        var profile = test.profile(modelName: "gpt-6.1-sol", endpoint: "https://api.openai.com/v1")
        profile.settings.responseSpeed = .fast
        test.select(profile, provider: test.provider)
        test.model.composer.effort = .maximum
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/verification/inference-selector", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try capture(
            VyronEffortControl().environmentObject(test.model),
            size: CGSize(width: 340, height: 54), to: directory.appendingPathComponent("selection-fast.png")
        )
        try capture(
            VyronEffortPopover().environmentObject(test.model),
            size: CGSize(width: 280, height: 200), to: directory.appendingPathComponent("popover-fast.png")
        )
        try capture(
            VyronInferenceSelectionLabel(
                modelName: "gpt-6.1-sol", effort: .extraHigh, speed: .standard, expanded: false
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.raised),
            size: CGSize(width: 340, height: 54), to: directory.appendingPathComponent("selection-extra-high.png")
        )
        try capture(
            VyronInferenceSelectionLabel(
                modelName: "gpt-6.1-sol", effort: .extraHigh, speed: .fast, expanded: false
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.raised),
            size: CGSize(width: 240, height: 54),
            to: directory.appendingPathComponent("selection-extra-high-narrow.png")
        )
        profile.selectedModel = "very-long-selected-model-name-with-a-quantization:q4_K_M"
        profile.endpoint = "http://localhost:1234/v1"
        test.select(profile, provider: test.provider)
        test.model.composer.effort = .ultra
        try capture(
            VyronEffortControl().environmentObject(test.model),
            size: CGSize(width: 240, height: 54), to: directory.appendingPathComponent("selection-narrow.png")
        )
        try capture(
            VyronEffortPopover().environmentObject(test.model),
            size: CGSize(width: 280, height: 200), to: directory.appendingPathComponent("popover-local.png")
        )
    }

    private func capture<Content: View>(_ content: Content, size: CGSize, to url: URL) throws {
        let renderer = ImageRenderer(content: content
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "en"))
            .frame(width: size.width, height: size.height)
            .background(Palette.canvas)
        )
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            throw XCTSkip("BLOCKED: Offscreen ImageRenderer unavailable; no window or app fallback permitted.")
        }
        XCTAssertEqual(image.width, Int(size.width * renderer.scale))
        XCTAssertEqual(image.height, Int(size.height * renderer.scale))
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: url, options: .atomic)
    }
}
