import AppKit
import SwiftUI
import XCTest
import VyronAutomation
@testable import Vyron

@MainActor
final class VyronChromeConnectionVisualTests: XCTestCase {
    func testCaptureSetupCardWithoutConnectingChrome() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let renderer = ImageRenderer(content: VyronChromeConnectionSetting(
            client: VyronChromeBridgeClient(root: root.appendingPathComponent(".build/unused-chrome-preview"))
        )
        .padding(VyronSettingsStyle.contentPadding)
        .frame(width: 680, height: 440)
        .background(Palette.canvas)
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            throw XCTSkip("BLOCKED: Offscreen Chrome setup rendering is unavailable.")
        }
        let directory = root.appendingPathComponent(".build/verification/chrome", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent("connection-settings.png"), options: .atomic)
    }
}
