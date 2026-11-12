import AppKit
import SwiftUI
import XCTest
@testable import Vyron

/// Solid-color offscreen fixtures exercise the real layout without creating a window or app model.
@MainActor
final class VyronWorkspaceSplitRenderTests: XCTestCase {
    func testOpeningEitherEdgePlacesThePanelBesideTheContent() throws {
        let sidebar = VyronWorkspaceSplitConfiguration.sidebar(minimumContentWidth: 560)
        let inspector = VyronWorkspaceSplitConfiguration.inspector

        let left = try render(split(isPresented: true, configuration: sidebar), width: 1_000)
        XCTAssertTrue(try color(in: left, at: 20).redComponent > 0.9)
        XCTAssertTrue(try color(in: left, at: 980).greenComponent > 0.9)

        let right = try render(split(isPresented: true, configuration: inspector), width: 1_000)
        XCTAssertTrue(try color(in: right, at: 20).greenComponent > 0.9)
        XCTAssertTrue(try color(in: right, at: 980).redComponent > 0.9)
    }

    func testClosingEitherEdgeReturnsItsEntireWidthToTheContent() throws {
        let configurations = [
            VyronWorkspaceSplitConfiguration.sidebar(minimumContentWidth: 560),
            .inspector
        ]
        for configuration in configurations {
            let image = try render(split(isPresented: false, configuration: configuration), width: 1_000)

            for x in [0, 299, 500, 669, 999] {
                let sample = try color(in: image, at: x)
                XCTAssertGreaterThan(sample.greenComponent, 0.9)
                XCTAssertLessThan(sample.redComponent, 0.1)
            }
        }
    }

    func testNestedPanelsKeepConversationVisibleAtTheMinimumWindowSize() throws {
        let sidebar = VyronWorkspaceSplitConfiguration.sidebar(minimumContentWidth: 821)
        let content = VyronWorkspaceSplitView(isPresented: true, configuration: sidebar) {
            Color(nsColor: .red)
        } content: {
            VyronWorkspaceSplitView(isPresented: true, configuration: .inspector) {
                Color(nsColor: .blue)
            } content: {
                Color(nsColor: .green)
            }
        }
        let image = try render(content, width: 1_042)

        XCTAssertGreaterThan(try color(in: image, at: 0).redComponent, 0.9)
        XCTAssertGreaterThan(try color(in: image, at: 219).redComponent, 0.9)
        XCTAssertGreaterThan(try color(in: image, at: 221).greenComponent, 0.9)
        XCTAssertGreaterThan(try color(in: image, at: 780).greenComponent, 0.9)
        XCTAssertGreaterThan(try color(in: image, at: 782).blueComponent, 0.9)
        XCTAssertGreaterThan(try color(in: image, at: 1_041).blueComponent, 0.9)
    }

    private func split(
        isPresented: Bool,
        configuration: VyronWorkspaceSplitConfiguration
    ) -> some View {
        VyronWorkspaceSplitView(isPresented: isPresented, configuration: configuration) {
            Color(nsColor: .red)
        } content: {
            Color(nsColor: .green)
        }
    }

    private func render<Content: View>(_ content: Content, width: CGFloat) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: content
            .frame(width: width, height: 80)
        )
        renderer.scale = 1
        guard let image = renderer.cgImage else {
            throw XCTSkip("BLOCKED: Offscreen ImageRenderer unavailable; no application/window fallback permitted.")
        }
        XCTAssertEqual(image.width, Int(width))
        XCTAssertEqual(image.height, 80)
        return NSBitmapImageRep(cgImage: image)
    }

    private func color(in image: NSBitmapImageRep, at x: Int) throws -> NSColor {
        try XCTUnwrap(image.colorAt(x: x, y: 40)?.usingColorSpace(.deviceRGB))
    }
}
