import AppKit
import SwiftUI
import XCTest
@testable import Vyron

/// Production tab strip and home only; no web view, app, window, or provider is started.
@MainActor
final class VyronWorkspaceTabsRenderTests: XCTestCase {
    func testCaptureTabsAndNewTabHomeAtRegularAndNarrowWidths() throws {
        guard ProcessInfo.processInfo.environment["VYRON_CAPTURE_WORKSPACE_TABS"] == "1" else {
            throw XCTSkip("Set VYRON_CAPTURE_WORKSPACE_TABS=1 for offscreen tab verification.")
        }
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.model.composer.mode = .agent
        let library = VyronWorkspaceLibraryModel(directory: test.directory.appendingPathComponent("Library"))
        let presentation = VyronWorkspaceTabsPresentation(library: library)
        XCTAssertTrue(library.addLink(title: "Engineering notes", address: "https://example.com/engineering"))
        XCTAssertTrue(library.addLink(title: "Project dashboard", address: "https://example.com/dashboard"))
        let website = try XCTUnwrap(URL(string: "https://example.com"))
        // Populate tab metadata directly so the website has no browser session or WebKit content.
        XCTAssertNotNil(presentation.tabs.openWebsite(website))
        let homeID = try XCTUnwrap(presentation.tabs.newTab())
        XCTAssertEqual(presentation.tabs.selectedID, homeID)
        XCTAssertTrue(presentation.browsers.isEmpty)
        XCTAssertTrue(presentation.pageSessions.isEmpty)

        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/verification/workspace-tabs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let home = VStack(spacing: 0) {
            VyronWorkspaceTabBar()
            VyronWorkspaceToolsView()
                .padding(VyronWorkspaceToolsStyle.sectionSpacing)
            Spacer(minLength: 0)
        }
        .environmentObject(test.model)
        .environmentObject(library)
        .environmentObject(presentation)

        let regular = try capture(
            home, size: CGSize(width: 640, height: 650),
            to: directory.appendingPathComponent("tabs-home.png")
        )
        for index in 0..<3 {
            assertVisibleTab(regular, at: index, containerWidth: 640)
        }
        let narrow = try capture(
            home, size: CGSize(width: 420, height: 650),
            to: directory.appendingPathComponent("tabs-narrow.png")
        )
        for index in 0..<3 {
            assertVisibleTab(narrow, at: index, containerWidth: 420)
        }
        for image in [regular, narrow] {
            let width = CGFloat(image.width) / 2
            let region = CGRect(x: 0, y: VyronWorkspaceTabsStyle.tabBarHeight, width: width, height: 200)
            XCTAssertGreaterThan(foregroundCount(image, in: region), 100, "Tools home must remain visible.")
        }
        // Address fields, page editors, and websites need native controls and are outside this capture.
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertFalse(test.model.modelSelection.isConnected)
        XCTAssertTrue(test.model.newSideChatSessions.isEmpty)
        XCTAssertTrue(presentation.browsers.isEmpty)
        XCTAssertTrue(presentation.pageSessions.isEmpty)
        XCTAssertNil(library.errorMessage)
    }

    private func assertVisibleTab(_ image: CGImage, at index: Int, containerWidth: CGFloat) {
        let tabWidth = VyronWorkspaceTabsStyle.tabItemWidth(containerWidth: containerWidth, count: 3)
        let tabStep = tabWidth + VyronWorkspaceTabsStyle.compactSpacing
        let region = CGRect(
            x: CGFloat(index) * tabStep + VyronWorkspaceTabsStyle.compactSpacing,
            y: 0,
            width: tabWidth,
            height: VyronWorkspaceTabsStyle.tabBarHeight
        )
        XCTAssertGreaterThan(
            foregroundCount(image, in: region), 15,
            "Tab \(index + 1) must display foreground content at width \(containerWidth)."
        )
    }

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

    private func foregroundCount(_ image: CGImage, in region: CGRect) -> Int {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let scale: CGFloat = 2
        let minX = max(0, Int(region.minX * scale))
        let maxX = min(image.width, Int(region.maxX * scale))
        let minY = max(0, Int(region.minY * scale))
        let maxY = min(image.height, Int(region.maxY * scale))
        var brightSamples = 0
        for y in stride(from: minY, to: maxY, by: 2) {
            for x in stride(from: minX, to: maxX, by: 2) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                    color.redComponent + color.greenComponent + color.blueComponent > 1.5 {
                    brightSamples += 1
                }
            }
        }
        return brightSamples
    }
}
