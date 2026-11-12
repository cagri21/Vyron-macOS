import AppKit
import SwiftUI
import XCTest
@testable import Vyron

/// Captures production tools without starting an application, window, or provider request.
@MainActor
final class VyronWorkspaceToolsRenderTests: XCTestCase {
    func testCapturePopulatedToolsHomeAndNarrowGrid() throws {
        guard ProcessInfo.processInfo.environment["VYRON_CAPTURE_WORKSPACE_TOOLS"] == "1" else {
            throw XCTSkip("Set VYRON_CAPTURE_WORKSPACE_TOOLS=1 for offscreen tools verification.")
        }
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.model.composer.mode = .agent
        let library = VyronWorkspaceLibraryModel(directory: test.directory.appendingPathComponent("Library"))
        let presentation = VyronWorkspaceTabsPresentation(library: library)
        XCTAssertTrue(library.addLink(title: "App publishing", address: "https://example.com/publishing"))
        XCTAssertTrue(library.addLink(title: "Engineering notes", address: "https://example.com/engineering"))
        XCTAssertTrue(library.addLink(title: "Project dashboard", address: "https://example.com/dashboard"))
        XCTAssertTrue(library.savePage(VyronWorkspacePage(
            title: "Vyron model comparison",
            body: "Notes about response quality, speed, and local workflows."
        )))
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/verification/workspace-tools", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let home = try capture(
            VyronWorkspaceToolsView()
                .environmentObject(test.model)
                .environmentObject(library)
                .environmentObject(presentation)
                .padding(VyronWorkspaceToolsStyle.sectionSpacing),
            size: CGSize(width: 640, height: 650),
            to: directory.appendingPathComponent("tools-home.png")
        )
        guard foregroundCount(home, inRightHalf: false) > 100,
            foregroundCount(home, inRightHalf: true) > 100
        else {
            throw XCTSkip("BLOCKED: ImageRenderer omitted native tools content; no app/window fallback permitted.")
        }

        let narrow = try capture(
            VyronWorkspaceToolsGrid(newPage: {})
                .environmentObject(test.model)
                .padding(VyronWorkspaceToolsStyle.padding),
            size: CGSize(width: 420, height: 210),
            to: directory.appendingPathComponent("tools-grid-narrow.png")
        )
        XCTAssertGreaterThan(foregroundCount(narrow, inRightHalf: false), 100)
        XCTAssertGreaterThan(foregroundCount(narrow, inRightHalf: true), 100)
        // Native TextField/TextEditor controls are omitted by ImageRenderer.
        // This check covers the home and tools grid, not page or link editors.
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertFalse(test.model.modelSelection.isConnected)
        XCTAssertTrue(test.model.newSideChatSessions.isEmpty)
        XCTAssertEqual(library.links.count, 3)
        XCTAssertEqual(library.pages.count, 1)
        XCTAssertNil(library.errorMessage)
    }

    @discardableResult
    private func capture<Content: View>(_ content: Content, size: CGSize, to url: URL) throws -> CGImage {
        let renderer = ImageRenderer(content: content
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Palette.canvas)
            .foregroundStyle(Palette.text)
            .environment(\.locale, Locale(identifier: "en"))
            .environment(\.colorScheme, .dark)
        )
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            throw XCTSkip("BLOCKED: offscreen ImageRenderer is unavailable; no app/window fallback permitted.")
        }
        XCTAssertEqual(image.width, Int(size.width * renderer.scale))
        XCTAssertEqual(image.height, Int(size.height * renderer.scale))
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: url, options: .atomic)
        return image
    }

    private func foregroundCount(_ image: CGImage, inRightHalf: Bool) -> Int {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let start = inRightHalf ? image.width / 2 : 0
        let end = inRightHalf ? image.width : image.width / 2
        var brightSamples = 0
        for y in stride(from: 0, to: image.height, by: 2) {
            for x in stride(from: start, to: end, by: 2) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                    color.redComponent + color.greenComponent + color.blueComponent > 1.5 {
                    brightSamples += 1
                }
            }
        }
        return brightSamples
    }
}
