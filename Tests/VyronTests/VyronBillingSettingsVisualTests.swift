import AppKit
import SwiftUI
import XCTest
@testable import Vyron

/// A static production card can be rendered safely; the signed-in WebKit page is not opened by this check.
@MainActor
final class VyronBillingSettingsVisualTests: XCTestCase {
    func testCaptureActualBillingEntryCardWithoutLoadingAWebsite() throws {
        guard ProcessInfo.processInfo.environment["VYRON_CAPTURE_BILLING_SETTINGS"] == "1" else {
            throw XCTSkip("Set VYRON_CAPTURE_BILLING_SETTINGS=1 for the offline card snapshot.")
        }
        let renderer = ImageRenderer(content: VStack(alignment: .leading, spacing: VyronBillingStyle.sectionSpacing) {
            Text(VyronBillingText.title).font(VyronSettingsStyle.title).foregroundStyle(Palette.text)
            VyronOpenAIBillingCard(open: {})
        }
        .padding(VyronSettingsStyle.contentPadding)
        .frame(width: 650, height: 310)
        .background(Palette.canvas)
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            throw XCTSkip("BLOCKED: Offscreen card rendering unavailable; no window or web-view fallback permitted.")
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent(".build/verification/billing-settings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent("billing-card.png"), options: .atomic)
    }
}
